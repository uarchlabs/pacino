// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// perf_top.sv -- THE HARNESS WRAPPER (PERF-002, perf_decisions.md PF-3,
// PF-4, PF-6). A testbench module, not RTL: it is Verilated with the RTL
// and driven by the C++ gasket (perf/src/harness/).
//
// It instantiates fe_top (dut) and the page table walker beside it
// (u_ptw, on the itlb_l2t_* group), as tb_fe_top does (fe_tb_dut.svh),
// and gives the gasket plain ports in place of the packed groups:
//   - the decode output, 8 wide: each slot's ibuf packet fields and
//     decode's is_illegal
//   - the FTQ resolution, redirect and commit groups, field by field
//   - the L1I's TileLink link and the walker's memory port, as they are
//   - the CSR groups, set from csr_tb_pkg on csr_load (below)
// No RTL file is changed, and no signal is made public: the internal
// signals the counts need are read here by hierarchical reference and
// brought out as this module's ports (PF-3, PF-6):
//   fr_*         THE FETCH RECORD (PERF-003, PF-18): the FTQ's fetch
//                request (dut.ftq_ifu_req_val, _rdy, _idx, _start_pc,
//                _next_pc, _taken_val, _taken_pos), the flush that
//                discards a request presented with it, and the fetch
//                read port's slots in the request cycle
//                (dut.u_ftq.u_entry.fetch_rd_entry: slot_valid, taken,
//                pos, br_type, target, pred_src). pred_src is the
//                predictor that supplied the final prediction (PF-6)
//   pc_*         the predecode correction as the FTQ writes the entry:
//                dut.u_ftq.u_ifu pd_wr_val, pd_wr_idx, the corrected
//                slots w_corr_slot and the successor w_corr_succ
//   ew_*         the entry writes the record's checks read: allocation
//                and the p2 and p3 slot writes (dut.u_ftq.u_entry ports)
//   (PERF-002's pq_*, the slots of each decode slot's entry read at the
//   take, are removed by PERF-003: the record replaces them)
//   os_*, orc_*  THE ORACLE (PERF-003, PF-11): os_* the block at each BPU
//                stage, the slots its stage logic reads and its
//                predecessor's FTQ entry; orc_* the trace's direction
//                and target per slot, from the gasket, forced into
//                bp_cluster's predictor outputs (the oracle section)
//   obs_walk     a walk request accepted, itlb_l2t_req_val and _rdy
//   obs_pd_redir the predecode redirect, dut.ifu_ftq_mis_val
//   obs_p2_redir, obs_p3_redir
//                a BPU override at p2 or p3, any slot's valid of
//                dut.bpu_redir_p2 and dut.bpu_redir_p3
//   obs_l1i_req, obs_l1i_paddr, obs_l1i_rdy
//                the IFU's request on the L1I core link,
//                dut.ifu_l1i_req_val, _paddr, _rdy (the I-cache switch,
//                PF-19, reads them)
//   rc_*         THE RAS CLASSIFICATION (BP-151): the RAS state
//                (dut.u_bpu.u_ras tosr, tosw, bos, csp, c_cnt and both
//                arrays), its p2 inputs, pop outputs, op codes and pre-op
//                state (p2_op, p2_push_inc, p2_push_sat, p2_pre_tosr,
//                p2_pre_empty), its p3 view and registered op, its write
//                ports (sp_we, sp_waddr), the restore and the commit as
//                it receives them, the FTQ commit index, the rollback
//                index and the predecode redirect's position
//                (perf/src/harness/ras_class.h reads them)
//
// THE CSR GROUPS (PF-5). csr_load, sampled at a rising edge, resets the
// csr_tb_pkg shadow (csr_pkg reset values, CSR-7), sets U-mode (every
// PF-17 leaf has U set, so the trace runs as user code), writes
// satp (csr_satp, the image's satp line: Sv57, ASID 0, the root), and
// writes 0x7C0 and 0x7C1 from the cfg_* inputs; fe_cfg, fe_csr and
// ptw_csr are then packed from the shadow (csr_decisions.md CSR-2), as
// fe_tb_csr.svh's csr_sync does.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;
import csr_pkg::*;

module perf_top (
  input  logic                        clk,
  input  logic                        rstn,

  // ---- decode to the backend (FE-20) -------------------------------
  output logic [SLOTS-1:0]            pd_valid,
  output logic [VA_WIDTH-1:0]         pd_pc     [SLOTS],
  output logic [31:0]                 pd_instr  [SLOTS],
  output logic [FTQ_PD_POS_BITS-1:0]  pd_pos    [SLOTS],
  output logic [FTQ_IDX_BITS-1:0]     pd_idx    [SLOTS],
  output logic [1:0]                  pd_fault  [SLOTS],
  output logic [SLOTS-1:0]            pd_rvc,
  output logic [SLOTS-1:0]            pd_illegal,
  input  logic                        dec_ibuf_rdy,

  // ---- the FTQ resolution group, per port --------------------------
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_val,
  input  logic [FTQ_IDX_BITS-1:0]     rsv_idx    [NUM_RESOLVE_PORTS],
  input  logic [FTB_BR_POS_BITS-1:0]  rsv_pos    [NUM_RESOLVE_PORTS],
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_taken,
  input  logic [VA_WIDTH-1:0]         rsv_target [NUM_RESOLVE_PORTS],
  input  logic [2:0]                  rsv_type   [NUM_RESOLVE_PORTS],
  input  logic [NUM_RESOLVE_PORTS-1:0] rsv_mis,
  output logic [NUM_RESOLVE_PORTS-1:0] rsv_rdy,

  // ---- the FTQ redirect and commit groups --------------------------
  input  logic                        redir_val,
  input  logic [FTQ_IDX_BITS-1:0]     redir_idx,
  input  logic [FTB_BR_POS_BITS-1:0]  redir_pos,
  input  logic [VA_WIDTH-1:0]         redir_pc,
  input  logic                        redir_self,
  input  logic [1:0]                  redir_cause,
  input  logic                        redir_taken,
  // BP-153: the resolved type of the redirecting branch (bp_br_type_e)
  // and its length. Every image word is 32 bits, so _rvc is driven 0.
  input  logic [2:0]                  redir_type,
  input  logic                        commit_val,
  input  logic [FTQ_PTR_BITS-1:0]     commit_idx,

  // ---- the L1I's l2-side TileLink link -----------------------------
  output logic                        l1i_a_valid,
  input  logic                        l1i_a_ready,
  output logic [2:0]                  l1i_a_opcode,
  output logic [2:0]                  l1i_a_size,
  output logic [3:0]                  l1i_a_source,
  output logic [PA_WIDTH-1:0]         l1i_a_address,
  output logic [31:0]                 l1i_a_mask,
  input  logic                        l1i_d_valid,
  output logic                        l1i_d_ready,
  input  logic [2:0]                  l1i_d_opcode,
  input  logic [2:0]                  l1i_d_size,
  input  logic [3:0]                  l1i_d_source,
  input  logic                        l1i_d_denied,
  input  logic [255:0]                l1i_d_data,

  // ---- the walker's memory port (ptw_mem_interfaces.md) ------------
  output logic                        ptw_req_val,
  input  logic                        ptw_req_rdy,
  output logic                        ptw_req_op,
  output logic [PA_WIDTH-1:0]         ptw_req_paddr,
  output logic [63:0]                 ptw_req_cmp,
  output logic [63:0]                 ptw_req_swap,
  input  logic                        ptw_rsp_val,
  input  logic [63:0]                 ptw_rsp_data,
  input  logic                        ptw_rsp_err,

  // ---- the CSR groups (PF-5) ---------------------------------------
  input  logic                        csr_load,
  input  logic [63:0]                 csr_satp,
  input  logic                        cfg_sc_enable,
  input  logic                        cfg_ftb_fastpath_en,
  input  logic                        cfg_tage_enable_aging,
  input  logic                        cfg_ittage_enable_aging,
  input  logic [31:0]                 cfg_tage_aging_interval,
  input  logic [31:0]                 cfg_ittage_aging_interval,

  // ---- observation (PF-6), by hierarchical reference ---------------
  output logic                        obs_walk,
  // fe_cfg as fe_top receives it: sc, fast path, TAGE and ITTAGE aging
  // enables, then the two intervals.
  output logic [3:0]                  obs_cfg_en,
  output logic [31:0]                 obs_cfg_tage_int,
  output logic [31:0]                 obs_cfg_ittage_int,
  output logic                        obs_pd_redir,
  output logic                        obs_p2_redir,
  output logic                        obs_p3_redir,
  output logic                        obs_l1i_req,
  output logic [PA_WIDTH-1:0]         obs_l1i_paddr,
  output logic                        obs_l1i_rdy,
  output logic                        ftq_full,
  output logic                        ftq_empty,
  // PERF-004 Phase 4, THE CONFIGURATION PROBES: the design's own state
  // that shows each PF-5 setting taking effect, per slot, this cycle.
  //   cf_fp_use     a p2 conditional slot whose direction the FTB fast
  //                 path supplied (bp_cluster w_fp_use_p2, ftb_fastpath_en)
  //   cf_sc_hit     a p3 slot SC answered (bp_cluster w_sc_hit_p3,
  //                 sc_enable)
  //   cf_tg_epoch, cf_it_epoch
  //                 the TAGE and ITTAGE epochs (tage_cntrl, ittage_cntrl
  //                 lcl_epoch; aging enable and interval)
  //   cf_tg_decay, cf_it_decay
  //                 per tagged table, bit t-1: a p1 lookup whose entry's
  //                 effective useful value is below its stored one, the
  //                 decay the epoch applies (tage_cntrl ueff_p1 against
  //                 t_use_p1; ittage_cntrl u_eff against the USE field)
  output logic [NUM_PRED_SLOTS-1:0]   cf_fp_use,
  output logic [NUM_PRED_SLOTS-1:0]   cf_sc_hit,
  output logic [1:0]                  cf_tg_epoch [NUM_PRED_SLOTS],
  output logic [1:0]                  cf_it_epoch [NUM_PRED_SLOTS],
  output logic [TAGE_NUM_TABLES-2:0]  cf_tg_decay [NUM_PRED_SLOTS],
  output logic [IT_NUM_TABLES-2:0]    cf_it_decay [NUM_PRED_SLOTS],
  // PERF-004 Phase 5, THE SC DECISION at p3, per slot, for the event log
  // (PERF_EVLOG S lines): an SC answer for the p3 block (bp_cluster
  // w_sc_hit_p3), the block's index and the slot's position, the p2
  // direction and the p3 one the cluster takes (r_taken_p3, w_taken_p3),
  // the loop or fast-path hold (r_lp_use_p3 | r_fp_use_p3), and SC's
  // inputs and result (sc_cntrl: final_pred, lcl_tkn, TAGE's direction,
  // strong and medium bits, sc_sum, the threshold and the two choosers).
  output logic [NUM_PRED_SLOTS-1:0]   sd_hit,
  output logic [FTQ_IDX_BITS-1:0]     sd_idx,
  output logic [FTB_BR_POS_BITS-1:0]  sd_pos [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   sd_p2tk,
  output logic [NUM_PRED_SLOTS-1:0]   sd_p3tk,
  output logic [NUM_PRED_SLOTS-1:0]   sd_hold,
  output logic [NUM_PRED_SLOTS-1:0]   sd_final,
  output logic [NUM_PRED_SLOTS-1:0]   sd_lcl,
  output logic [NUM_PRED_SLOTS-1:0]   sd_ttkn,
  output logic [NUM_PRED_SLOTS-1:0]   sd_thi,
  output logic [NUM_PRED_SLOTS-1:0]   sd_tmed,
  output logic [15:0]                 sd_sum [NUM_PRED_SLOTS],
  output logic [15:0]                 sd_thr,
  output logic [7:0]                  sd_chi,
  output logic [7:0]                  sd_cmed,
  // PERF-005 Phase 1, THE DECISION PROBES: why each slot's direction or
  // target came from its source, at p2 and p3, per slot (read only).
  //   dp2_*  the p2 block (bp_cluster r_val_p2, r_idx_p2): the FTB
  //          answered (w_ftb_valid_p2), the p1 return redirect
  //          (w_p1ret_any_p2), and per slot: a conditional slot
  //          (w_br_val_p2, COND), the loop and fast-path uses
  //          (w_lp_use_p2, w_fp_use_p2), TAGE's response present
  //          (w_tage_pred_rdy_p2) and for this entry (w_tage_hit_p2),
  //          its provider and alternate tables and which supplied the
  //          direction (tage_prm_comp, _alt_comp, _using_primary),
  //          ITTAGE's response, its entry match and hit, the RAS peek
  //          valid
  //   dp3_*  the p3 block (r_val_p3, r_idx_p3): per slot, a conditional
  //          slot (r_slot_p3), SC's answer for this entry (w_sc_hit_p3),
  //          the loop or fast-path hold, the p2 and the SC direction,
  //          SC's own direction and the corner (sc_chooser)
  output logic                        dp2_val,
  output logic [FTQ_IDX_BITS-1:0]     dp2_idx,
  output logic                        dp2_ftb,
  output logic                        dp2_p1ret,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_cond,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_lp,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_fp,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_trdy,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_thit,
  output logic [2:0]                  dp2_prm [NUM_PRED_SLOTS],
  output logic [2:0]                  dp2_alt [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   dp2_usep,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_irdy,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_ibid,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_ihit,
  output logic [NUM_PRED_SLOTS-1:0]   dp2_pkv,
  output logic                        dp3_val,
  output logic [FTQ_IDX_BITS-1:0]     dp3_idx,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_cond,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_schit,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_hold,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_p2tk,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_sctk,
  output logic [NUM_PRED_SLOTS-1:0]   dp3_lcl,
  output logic [1:0]                  dp3_chs [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   dp2_ttk,
  // PERF-005 Phase 2, THE FAST-PATH PROBES (read only), on ftb_cntrl
  // (dut.u_bpu.u_ftb.u_ftb_cntrl) and ftq_ftb_sched (dut.u_ftq.
  // u_ftb_sched), field i = br0, br1:
  //   fq_*  the p2 read: ftb_valid_p2, the set (pred_set_idx_p1 of the
  //         cycle before) and way (q_way_p2), ftb_brI_valid_p2, the
  //         position and conf (q_brI_pos, q_brI_conf), ftb_fastpath_p2,
  //         ftb_fastpath_en
  //   fu_*  the update (ftb_upd_valid_u0): set and way, upd_hit, is_br,
  //         upd_past, inplace, the position and outcome, the read conf
  //         (fld_old.conf), and the written fields (upd_new.brI valid,
  //         pos, conf)
  //   fs_*  the scheduler, per channel: an FTB-bound conditional
  //         accepted (w_acc_ftb, upd[c].is_br), and dropped (S5)
  output logic                        fq_val,
  output logic [FTB_IDX_BITS-1:0]     fq_set,
  output logic [FTB_WAY_BITS-1:0]     fq_way,
  output logic [1:0]                  fq_bv,
  output logic [FTB_BR_POS_BITS-1:0]  fq_pos [2],
  output logic [FTB_CONF_WIDTH-1:0]   fq_conf [2],
  output logic [1:0]                  fq_fp,
  output logic                        fq_en,
  output logic                        fu_val,
  output logic [FTB_IDX_BITS-1:0]     fu_set,
  output logic [FTB_WAY_BITS-1:0]     fu_way,
  output logic                        fu_hit,
  output logic                        fu_isbr,
  output logic                        fu_past,
  output logic                        fu_inpl,
  output logic [FTB_BR_POS_BITS-1:0]  fu_pos,
  output logic                        fu_tkn,
  output logic [FTB_CONF_WIDTH-1:0]   fu_oconf,
  output logic [1:0]                  fu_nv,
  output logic [FTB_BR_POS_BITS-1:0]  fu_npos [2],
  output logic [FTB_CONF_WIDTH-1:0]   fu_nconf [2],
  output logic [NUM_RESOLVE_PORTS-1:0] fs_acc,
  output logic [NUM_RESOLVE_PORTS-1:0] fs_drop,
  // PERF-005 Phase 3, THE TAGE PROBES (read only), on dut.u_bpu.u_tage
  // and the cluster's history ports; [t*NUM_PRED_SLOTS+s] is table t
  // (0 = T0), slot s:
  //   tl_*  the lookup as the tables see it, at the competing stage
  //         (u_tage_arb cntrl_pred_val_p0, cntrl_pred_inp_p0 pc and
  //         branch_id), its index and tag per table (w_idx_p0,
  //         w_tag_p0), the folds (w_folded tage_tN_*), and whether it
  //         came from the prediction queue (!pq_empty) or in a rollback
  //         cycle (w_rollback_valid)
  //   hw_*  the p1 history write (w_ckpt_wr_en, _idx,
  //         w_hist_num_branches, w_hist_pred_taken); hr_* the rollback
  //         (w_rollback_valid, _ckpt_idx, w_rb_corr, w_rb_n, w_rb_tkn)
  //   tp_*  the p1 read (tage_cntrl pred_val_p1, t_idx_r1, w_hit_p1,
  //         w_cntrl_bits_p1)
  //   tu_*  the update at the competing stage (cntrl_upd_val_u0 and
  //         the fields of cntrl_upd_inp_u0), lcl_epoch
  //   tw_*  every RAM write of every table and slot (ram_wen_n low:
  //         address, data, byte-write enables)
  output logic [NUM_PRED_SLOTS-1:0]   tl_val,
  output logic [FTQ_IDX_BITS-1:0]     tl_bid [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         tl_pc [NUM_PRED_SLOTS],
  output logic [15:0]                 tl_idx [5*NUM_PRED_SLOTS],
  output logic [15:0]                 tl_tag [5*NUM_PRED_SLOTS],
  output logic [15:0]                 tl_fh [12],
  output logic                        tl_q,
  output logic                        tl_rb,
  output logic                        hw_val,
  output logic [FTQ_IDX_BITS-1:0]     hw_idx,
  output logic [1:0]                  hw_n,
  output logic [1:0]                  hw_tkn,
  output logic                        hr_val,
  output logic [FTQ_IDX_BITS-1:0]     hr_idx,
  output logic                        hr_corr,
  output logic [1:0]                  hr_n,
  output logic [1:0]                  hr_tkn,
  // the history pointer and the 16 GHR bits behind it, newest first
  // (PERF-005 Phase 3, the history check's logf only)
  output logic [15:0]                 hp_ptr,
  output logic [15:0]                 hp_win,
  output logic [NUM_PRED_SLOTS-1:0]   tp_val,
  output logic [15:0]                 tp_idx [5*NUM_PRED_SLOTS],
  output logic [15:0]                 tp_tag [5*NUM_PRED_SLOTS],
  output logic [5*NUM_PRED_SLOTS-1:0] tp_hit,
  output logic [15:0]                 tp_cb [5*NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   tu_val,
  output logic [FTQ_IDX_BITS-1:0]     tu_bid [NUM_PRED_SLOTS],
  output logic [15:0]                 tu_pidx [NUM_PRED_SLOTS],
  output logic [15:0]                 tu_aidx [NUM_PRED_SLOTS],
  output logic [15:0]                 tu_cidx [NUM_PRED_SLOTS],
  output logic [7:0]                  tu_ctag [NUM_PRED_SLOTS],
  output logic [2:0]                  tu_pcmp [NUM_PRED_SLOTS],
  output logic [2:0]                  tu_acmp [NUM_PRED_SLOTS],
  output logic [2:0]                  tu_ccmp [NUM_PRED_SLOTS],
  output logic [2:0]                  tu_pctr [NUM_PRED_SLOTS],
  output logic [2:0]                  tu_actr [NUM_PRED_SLOTS],
  output logic [1:0]                  tu_puse [NUM_PRED_SLOTS],
  output logic [1:0]                  tu_ause [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   tu_ptk,
  output logic [NUM_PRED_SLOTS-1:0]   tu_atk,
  output logic [NUM_PRED_SLOTS-1:0]   tu_up,
  output logic [NUM_PRED_SLOTS-1:0]   tu_tk,
  output logic [NUM_PRED_SLOTS-1:0]   tu_res,
  output logic [NUM_PRED_SLOTS-1:0]   tu_mis,
  output logic [1:0]                  tu_ep [NUM_PRED_SLOTS],
  // the use_alt_on_na counter of each slot, as registered (PERF-005
  // Phase 3: the harness re-derives it, tu_chk_uaon)
  output logic [3:0]                  tu_uaon [NUM_PRED_SLOTS],
  // PERF-005 Phase 3, THE SC PROBES (read only, dut.u_bpu.u_sc.
  // u_sc_cntrl): at p3 the five counters read (t_ctr_p3), TAGE's
  // extended counter, the override and the corner; at the update the
  // valid, the metadata (local, final and TAGE directions, |sum|, the
  // corner, the counters read), the outcome, the counter write and its
  // data, and the global state now and next (threshold, TC, the two
  // choosers) with the winning slot (w_sel).
  output logic [7:0]                  sd_ctr [5*NUM_PRED_SLOTS],
  output logic [7:0]                  sd_ext [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   sd_ovr,
  output logic [1:0]                  sd_chs [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]   su_val,
  output logic [NUM_PRED_SLOTS-1:0]   su_lcl,
  output logic [NUM_PRED_SLOTS-1:0]   su_fin,
  output logic [NUM_PRED_SLOTS-1:0]   su_ttk,
  output logic [NUM_PRED_SLOTS-1:0]   su_res,
  output logic [NUM_PRED_SLOTS-1:0]   su_wr,
  output logic [15:0]                 su_abs [NUM_PRED_SLOTS],
  output logic [1:0]                  su_chs [NUM_PRED_SLOTS],
  output logic [7:0]                  su_ctr [5*NUM_PRED_SLOTS],
  output logic [7:0]                  su_wd [5*NUM_PRED_SLOTS],
  output logic [15:0]                 su_thr,
  output logic [15:0]                 su_thr_d,
  output logic [7:0]                  su_tc,
  output logic [7:0]                  su_tc_d,
  output logic [7:0]                  su_chi_d,
  output logic [7:0]                  su_cmed_d,
  output logic                        su_wsel,
  output logic [5*NUM_PRED_SLOTS-1:0] tw_we,
  output logic [15:0]                 tw_addr [5*NUM_PRED_SLOTS],
  output logic [15:0]                 tw_din [5*NUM_PRED_SLOTS],
  output logic [15:0]                 tw_bweb [5*NUM_PRED_SLOTS],

  // ---- the fetch record (PERF-003, PF-18), by hierarchical reference
  // The fetch request (dut.ftq_ifu_*, ftq_ifu.sv request) and the
  // flush that discards a request presented with it (ftq_ifu.sv 5).
  output logic                        fr_req_val,
  output logic                        fr_req_rdy,
  output logic                        fr_flush_val,
  output logic [FTQ_IDX_BITS-1:0]     fr_idx,
  output logic [FTQ_IDX_BITS-1:0]     fr_rd_idx,
  output logic [VA_WIDTH-1:0]         fr_start_pc,
  output logic [VA_WIDTH-1:0]         fr_next_pc,
  output logic                        fr_taken_val,
  output logic [FTB_BR_POS_BITS-1:0]  fr_taken_pos,
  // The fetch read port's slots in the request cycle
  // (dut.u_ftq.u_entry.fetch_rd_entry, which writes through p3).
  output logic [NUM_PRED_SLOTS-1:0]   fr_s_val,
  output logic [NUM_PRED_SLOTS-1:0]   fr_s_taken,
  output logic [FTB_BR_POS_BITS-1:0]  fr_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  fr_s_type [NUM_PRED_SLOTS],
  output logic [2:0]                  fr_s_src [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         fr_s_tgt [NUM_PRED_SLOTS],
  // The predecode correction as the FTQ writes it: pd_wr_val and _idx
  // (the gen-tested, R3-gated redirect), the corrected slots and the
  // successor re-derived over them (dut.u_ftq.u_ifu w_corr_slot,
  // w_corr_succ, ftq_ifu.sv 7).
  output logic                        pc_val,
  output logic [FTQ_IDX_BITS-1:0]     pc_idx,
  output logic [VA_WIDTH-1:0]         pc_succ,
  output logic [NUM_PRED_SLOTS-1:0]   pc_s_val,
  output logic [NUM_PRED_SLOTS-1:0]   pc_s_taken,
  output logic [FTB_BR_POS_BITS-1:0]  pc_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  pc_s_type [NUM_PRED_SLOTS],
  output logic [2:0]                  pc_s_src [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]         pc_s_tgt [NUM_PRED_SLOTS],
  // The entry writes the late-write check reads: allocation, and the
  // p2 and p3 slot writes (dut.u_ftq.u_entry ports).
  output logic                        ew_alloc_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_alloc_idx,
  output logic                        ew_p2_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_p2_idx,
  output logic                        ew_p3_val,
  output logic [FTQ_IDX_BITS-1:0]     ew_p3_idx,
  output logic [VA_WIDTH-1:0]         ew_alloc_pc,

  // ---- THE ORACLE (PERF-003, PF-11) ----------------------------------
  // The block at each BPU stage (bp_cluster r_val_pN, r_pc_pN,
  // r_idx_pN) and the slots its stage logic reads: p1 the registered
  // uBTB slots, p2 the FTB classification (w_br_val_p2, w_pos_p2,
  // w_br_type_p2), p3 the registered p2 slots (r_slot_p3).
  output logic                        os_p1_val,
  output logic [VA_WIDTH-1:0]         os_p1_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p1_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p1_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p1_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p1_s_type [NUM_PRED_SLOTS],
  output logic                        os_p2_val,
  output logic [VA_WIDTH-1:0]         os_p2_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p2_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p2_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p2_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p2_s_type [NUM_PRED_SLOTS],
  // PERF-004: the p1 view at p2 (bp_cluster r_slot_p2), whose returns
  // the RAS pops at p2 on an FTB miss and redirects to (BP-154 R2,
  // w_p1ret_redir_p2); the gasket forces that pop as the FTB slots' one.
  output logic [NUM_PRED_SLOTS-1:0]   os_p2_p1_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p2_p1_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p2_p1_s_type [NUM_PRED_SLOTS],
  output logic                        os_p3_val,
  output logic [VA_WIDTH-1:0]         os_p3_pc,
  output logic [FTQ_IDX_BITS-1:0]     os_p3_idx,
  output logic [NUM_PRED_SLOTS-1:0]   os_p3_s_val,
  output logic [FTB_BR_POS_BITS-1:0]  os_p3_s_pos [NUM_PRED_SLOTS],
  output logic [2:0]                  os_p3_s_type [NUM_PRED_SLOTS],
  // The FTQ entry before each stage's block (its predecessor, whose
  // prediction gave the block's PC): start, fall-through and slots, from
  // dut.u_ftq.u_entry.r_arr; [0] p1, [1] p2, [2] p3.
  output logic [VA_WIDTH-1:0]         os_pr_pc [3],
  output logic [VA_WIDTH-1:0]         os_pr_pft [3],
  output logic [NUM_PRED_SLOTS-1:0]   os_pr_s_val [3],
  output logic [NUM_PRED_SLOTS-1:0]   os_pr_s_taken [3],
  output logic [FTB_BR_POS_BITS-1:0]  os_pr_s_pos [3][NUM_PRED_SLOTS],
  // The trace's value for each slot, from the gasket: _den forces the
  // direction to _dir, _ten the target to _tgt; p1 _ret forces the RAS
  // top of stack (a return slot) to _dir and _tgt; p2 _jten forces the
  // block's jump target to _jtgt. A slot with no enable keeps the
  // predictor's own value. orc_on is --oracle.
  input  logic                        orc_on,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_dir,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_ten,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p1_ret,
  input  logic [VA_WIDTH-1:0]         orc_p1_tgt [NUM_PRED_SLOTS],
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_dir,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p2_ten,
  input  logic [VA_WIDTH-1:0]         orc_p2_tgt [NUM_PRED_SLOTS],
  input  logic                        orc_p2_jten,
  input  logic [VA_WIDTH-1:0]         orc_p2_jtgt,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p3_den,
  input  logic [NUM_PRED_SLOTS-1:0]   orc_p3_dir,

  // ---- THE RAS CLASSIFICATION (BP-151), by hierarchical reference ----
  // Observation only: the RAS state (dut.u_bpu.u_ras), its p2 and p3
  // operations as the scan forms them, its array write ports, and the
  // restore and commit groups as the RAS receives them.
  output logic [RAS_PTR_BITS-1:0]        rc_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_tosw,
  output logic [RAS_PTR_BITS-1:0]        rc_bos,
  output logic [RAS_COMMIT_PTR_BITS-1:0] rc_csp,
  output logic [RAS_COMMIT_PTR_BITS:0]   rc_ccnt,
  output logic [VA_WIDTH-1:0]            rc_spec_addr [RAS_SPEC_ENTRIES],
  output logic [RAS_PTR_BITS-1:0]        rc_spec_nos  [RAS_SPEC_ENTRIES],
  output logic [RAS_RCTR_WIDTH-1:0]      rc_spec_rctr [RAS_SPEC_ENTRIES],
  output logic [RAS_SPEC_ENTRIES-1:0]    rc_spec_bot,
  output logic [VA_WIDTH-1:0]            rc_cmt_addr  [RAS_COMMIT_ENTRIES],
  // p2: the inputs, the pop outputs, the op and the pre-op state per slot
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_val,
  output logic [2:0]                     rc_p2_type   [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]            rc_p2_ft     [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_popv,
  output logic [VA_WIDTH-1:0]            rc_p2_popa   [NUM_PRED_SLOTS],
  output logic [1:0]                     rc_p2_op     [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_inc,
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_sat,
  output logic [RAS_PTR_BITS-1:0]        rc_p2_pre    [NUM_PRED_SLOTS],
  output logic [NUM_PRED_SLOTS-1:0]      rc_p2_pre_empty,
  output logic                           rc_keep,
  output logic                           rc_ftb_p2,
  // p3: the view and the registered p2 op per slot
  output logic [NUM_PRED_SLOTS-1:0]      rc_p3_val,
  output logic [2:0]                     rc_p3_type   [NUM_PRED_SLOTS],
  output logic [1:0]                     rc_p3_op     [NUM_PRED_SLOTS],
  output logic [VA_WIDTH-1:0]            rc_p3_ft     [NUM_PRED_SLOTS],
  // the speculative array write ports (ras.sv RAS_WR_PORTS)
  output logic [4*NUM_PRED_SLOTS-1:0]    rc_we,
  output logic [RAS_PTR_BITS-1:0]        rc_waddr     [4*NUM_PRED_SLOTS],
  // the restore and the commit, as the RAS receives them
  output logic                           rc_rs_val,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_tosw,
  output logic [RAS_PTR_BITS-1:0]        rc_rs_bos,
  output logic                           rc_cm_val,
  output logic [2:0]                     rc_cm_type,
  output logic [VA_WIDTH-1:0]            rc_cm_addr,
  output logic [RAS_PTR_BITS-1:0]        rc_cm_tosr,
  output logic [RAS_PTR_BITS-1:0]        rc_cm_bos,
  output logic [FTQ_IDX_BITS-1:0]        rc_cm_idx,
  // the entry a restore names, and the predecode redirect's position
  output logic [FTQ_IDX_BITS-1:0]        rc_rs_idx,
  output logic [FTQ_PD_POS_BITS-1:0]     rc_pd_pos,
  // BP-152: the commit-stack index a p2 pop on an empty stack read (A1),
  // and the C1 operation on a restore: valid, type, the address a call
  // pushes, and its allocation (the restore scan's port 3, RS_P_PUSH).
  output logic [RAS_COMMIT_PTR_BITS-1:0] rc_p2_fbi   [NUM_PRED_SLOTS],
  output logic                           rc_pd_val,
  output logic [2:0]                     rc_pd_type,
  output logic [VA_WIDTH-1:0]            rc_pd_ret,
  output logic                           rc_pd_al,
  output logic [RAS_PTR_BITS-1:0]        rc_pd_waddr,
  // BP-152, A1: the depth after each slot's p2 operation (its snapshot's
  // dep) and the committed depth, for the classifier's diagnostics.
  output logic [RAS_DEPTH_BITS-1:0]      rc_p2_dep   [NUM_PRED_SLOTS],
  output logic [RAS_DEPTH_BITS-1:0]      rc_dcm,
  // BP-152: the restore undid the named block's own push (ras_rs_undo).
  output logic                           rc_rs_undo,
  // BP-153: and its own pop (ras_rs_undo_pop, with a pop record).
  output logic                           rc_rs_undo_pop
);

  // ---- every fe_top port, the names fe_tb_dut.svh gives them -------
  decode_pkt_t     [SLOTS-1:0] decode_bundle;
  vec_decode_pkt_t [SLOTS-1:0] vec_decode_bundle;
  logic            [SLOTS-1:0] is_vector;
  ifu_pd_pkt_t                 pd_out [0:SLOTS-1];
  logic            [SLOTS-1:0] vtype_hazard;
  logic [NUM_RESOLVE_PORTS-1:0] bkend_ftq_rsv_val;
  ftq_resolve_t                bkend_ftq_rsv [0:NUM_RESOLVE_PORTS-1];
  logic [NUM_RESOLVE_PORTS-1:0] ftq_bkend_rsv_rdy;
  logic                        bkend_ftq_redir_val;
  logic [FTQ_IDX_BITS-1:0]     bkend_ftq_redir_idx;
  logic [FTB_BR_POS_BITS-1:0]  bkend_ftq_redir_pos;
  logic [VA_WIDTH-1:0]         bkend_ftq_redir_pc;
  logic                        bkend_ftq_redir_self;
  ftq_redir_cause_e            bkend_ftq_redir_cause;
  logic                        bkend_ftq_redir_taken;
  bp_br_type_e                 bkend_ftq_redir_type;   // BP-153
  logic                        bkend_ftq_redir_rvc;    // BP-153
  logic                        bkend_ftq_commit_val;
  logic [FTQ_PTR_BITS-1:0]     bkend_ftq_commit_idx;
  logic                        itlb_l2t_req_val;
  logic                        itlb_l2t_req_rdy;
  logic [VA_WIDTH-13:0]        itlb_l2t_vpn;
  logic [ASID_WIDTH-1:0]       itlb_l2t_asid;
  logic [VMID_WIDTH-1:0]       itlb_l2t_vmid;
  logic                        itlb_l2t_v;
  logic [1:0]                  itlb_l2t_tag;
  logic [1:0]                  itlb_l2t_acc;
  logic [1:0]                  itlb_l2t_priv;
  logic                        l2t_itlb_rsp_val;
  logic [1:0]                  l2t_itlb_tag;
  logic [1:0]                  l2t_itlb_status;
  logic [PPN_WIDTH-1:0]        l2t_itlb_ppn;
  logic [2:0]                  l2t_itlb_size;
  logic [PERM_WIDTH-1:0]       l2t_itlb_perm;
  logic [1:0]                  l2t_itlb_pbmt;
  logic [CAUSE_WIDTH-1:0]      l2t_itlb_cause;
  logic [FAULT_GPA_WIDTH-1:0]  l2t_itlb_gpa;
  logic [1:0]                  l2t_itlb_gpa_imp;
  logic                        cmt_ifu_maint_val;
  logic                        cmt_ifu_maint_rdy;
  logic                        cmt_ifu_maint_op;
  logic [PA_WIDTH-1:0]         cmt_ifu_maint_paddr;
  logic                        ifu_cmt_maint_ack;
  logic                        l1i_mem_a_valid;
  logic                        l1i_mem_a_ready;
  logic [2:0]                  l1i_mem_a_opcode;
  logic [2:0]                  l1i_mem_a_param;
  logic [2:0]                  l1i_mem_a_size;
  logic [3:0]                  l1i_mem_a_source;
  logic [PA_WIDTH-1:0]         l1i_mem_a_address;
  logic [31:0]                 l1i_mem_a_mask;
  logic [255:0]                l1i_mem_a_data;
  logic                        l1i_mem_a_corrupt;
  logic                        l1i_mem_d_valid;
  logic                        l1i_mem_d_ready;
  logic [2:0]                  l1i_mem_d_opcode;
  logic [2:0]                  l1i_mem_d_param;
  logic [2:0]                  l1i_mem_d_size;
  logic [3:0]                  l1i_mem_d_source;
  logic [1:0]                  l1i_mem_d_sink;
  logic                        l1i_mem_d_denied;
  logic [255:0]                l1i_mem_d_data;
  logic                        l1i_mem_d_corrupt;
  fe_csr_t                     fe_csr;
  fe_cfg_t                     fe_cfg;
  logic                        bkend_itlb_inv_val;
  logic [1:0]                  bkend_itlb_inv_op;
  logic                        bkend_itlb_inv_rs1_nz;
  logic                        bkend_itlb_inv_rs2_nz;
  logic [VA_WIDTH-13:0]        bkend_itlb_inv_vpn;
  logic [ASID_WIDTH-1:0]       bkend_itlb_inv_asid;
  logic [VMID_WIDTH-1:0]       bkend_itlb_inv_vmid;

  fe_top dut (.*);

  // ---- the walker, beside the top (MMU-1a) -------------------------
  logic                        ptw_mem_req_val;
  logic                        ptw_mem_req_rdy;
  logic                        ptw_mem_req_op;
  logic [PA_WIDTH-1:0]         ptw_mem_req_paddr;
  logic [63:0]                 ptw_mem_req_cmp;
  logic [63:0]                 ptw_mem_req_swap;
  logic                        mem_ptw_rsp_val;
  logic [63:0]                 mem_ptw_rsp_data;
  logic                        mem_ptw_rsp_err;
  ptw_csr_t                    ptw_csr;

  ptw u_ptw (.*);

  // ---- the decode output, slot by slot -----------------------------
  always_comb begin : pd_ports
    for (int i = 0; i < SLOTS; i++) begin
      pd_valid[i]   = pd_out[i].valid;
      pd_pc[i]      = pd_out[i].start_pc;
      pd_instr[i]   = pd_out[i].instr;
      pd_pos[i]     = pd_out[i].pos;
      pd_idx[i]     = pd_out[i].ftq_idx;
      pd_fault[i]   = pd_out[i].fault_cause;
      pd_rvc[i]     = pd_out[i].is_rvc;
      pd_illegal[i] = decode_bundle[i].is_illegal;
    end
  end

  // ---- the backend groups ------------------------------------------
  always_comb begin : be_ports
    for (int p = 0; p < NUM_RESOLVE_PORTS; p++) begin
      bkend_ftq_rsv[p]            = '0;
      bkend_ftq_rsv[p].ftq_idx    = rsv_idx[p];
      bkend_ftq_rsv[p].pos        = rsv_pos[p];
      bkend_ftq_rsv[p].taken      = rsv_taken[p];
      bkend_ftq_rsv[p].target     = rsv_target[p];
      bkend_ftq_rsv[p].br_type    = bp_br_type_e'(rsv_type[p]);
      bkend_ftq_rsv[p].mispredict = rsv_mis[p];
      bkend_ftq_rsv[p].is_rvc     = 1'b0;     // every image word is 32 bits
    end
    bkend_ftq_rsv_val     = rsv_val;
    rsv_rdy               = ftq_bkend_rsv_rdy;
    bkend_ftq_redir_val   = redir_val;
    bkend_ftq_redir_idx   = redir_idx;
    bkend_ftq_redir_pos   = redir_pos;
    bkend_ftq_redir_pc    = redir_pc;
    bkend_ftq_redir_self  = redir_self;
    bkend_ftq_redir_cause = ftq_redir_cause_e'(redir_cause);
    bkend_ftq_redir_taken = redir_taken;
    bkend_ftq_redir_type  = bp_br_type_e'(redir_type);
    bkend_ftq_redir_rvc   = 1'b0;         // every image word is 32 bits
    bkend_ftq_commit_val  = commit_val;
    bkend_ftq_commit_idx  = commit_idx;
    // No FENCE.I, cbo.inval or ITLB invalidate in a trace.
    cmt_ifu_maint_val     = 1'b0;
    cmt_ifu_maint_op      = 1'b0;
    cmt_ifu_maint_paddr   = '0;
    bkend_itlb_inv_val    = 1'b0;
    bkend_itlb_inv_op     = '0;
    bkend_itlb_inv_rs1_nz = 1'b0;
    bkend_itlb_inv_rs2_nz = 1'b0;
    bkend_itlb_inv_vpn    = '0;
    bkend_itlb_inv_asid   = '0;
    bkend_itlb_inv_vmid   = '0;
  end

  // ---- the memory links --------------------------------------------
  always_comb begin : mem_ports
    l1i_a_valid       = l1i_mem_a_valid;
    l1i_mem_a_ready   = l1i_a_ready;
    l1i_a_opcode      = l1i_mem_a_opcode;
    l1i_a_size        = l1i_mem_a_size;
    l1i_a_source      = l1i_mem_a_source;
    l1i_a_address     = l1i_mem_a_address;
    l1i_a_mask        = l1i_mem_a_mask;
    l1i_mem_d_valid   = l1i_d_valid;
    l1i_d_ready       = l1i_mem_d_ready;
    l1i_mem_d_opcode  = l1i_d_opcode;
    l1i_mem_d_param   = '0;
    l1i_mem_d_size    = l1i_d_size;
    l1i_mem_d_source  = l1i_d_source;
    l1i_mem_d_sink    = '0;
    l1i_mem_d_denied  = l1i_d_denied;
    l1i_mem_d_data    = l1i_d_data;
    l1i_mem_d_corrupt = 1'b0;
    ptw_req_val       = ptw_mem_req_val;
    ptw_mem_req_rdy   = ptw_req_rdy;
    ptw_req_op        = ptw_mem_req_op;
    ptw_req_paddr     = ptw_mem_req_paddr;
    ptw_req_cmp       = ptw_mem_req_cmp;
    ptw_req_swap      = ptw_mem_req_swap;
    mem_ptw_rsp_val   = ptw_rsp_val;
    mem_ptw_rsp_data  = ptw_rsp_data;
    mem_ptw_rsp_err   = ptw_rsp_err;
  end

  // ---- the CSR groups (PF-5), from the csr_tb_pkg shadow -----------
  always_ff @(posedge clk) begin : csr_groups
    if (csr_load) begin
      csr_tb_pkg::csr_reset();
      csr_tb_pkg::set_priv(CSR_PRV_U);
      csr_tb_pkg::csr_write(CSR_SATP_ADDR, csr_satp);
      csr_tb_pkg::set_sc_enable(cfg_sc_enable);
      csr_tb_pkg::set_ftb_fastpath_en(cfg_ftb_fastpath_en);
      csr_tb_pkg::set_tage_enable_aging(cfg_tage_enable_aging);
      csr_tb_pkg::set_ittage_enable_aging(cfg_ittage_enable_aging);
      csr_tb_pkg::set_tage_aging_interval(cfg_tage_aging_interval);
      csr_tb_pkg::set_ittage_aging_interval(cfg_ittage_aging_interval);
      fe_cfg  <= csr_tb_pkg::pack_fe_cfg();
      fe_csr  <= csr_tb_pkg::pack_fe_csr();
      ptw_csr <= csr_tb_pkg::pack_ptw_csr();
    end
  end

  // ---- observation, by hierarchical reference (PF-6) ---------------
  always_comb begin : observe
    obs_walk     = itlb_l2t_req_val && itlb_l2t_req_rdy;
    obs_cfg_en   = {fe_cfg.ittage_enable_aging, fe_cfg.tage_enable_aging,
                    fe_cfg.ftb_fastpath_en, fe_cfg.sc_enable};
    obs_cfg_tage_int   = fe_cfg.tage_aging_interval;
    obs_cfg_ittage_int = fe_cfg.ittage_aging_interval;
    obs_pd_redir = dut.ifu_ftq_mis_val;
    obs_p2_redir = 1'b0;
    obs_p3_redir = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      obs_p2_redir = obs_p2_redir | dut.bpu_redir_p2[s].valid;
      obs_p3_redir = obs_p3_redir | dut.bpu_redir_p3[s].valid;
    end
    obs_l1i_req   = dut.ifu_l1i_req_val;
    obs_l1i_paddr = dut.ifu_l1i_req_paddr;
    obs_l1i_rdy   = dut.ifu_l1i_req_rdy;
  end

  // ---- PERF-004 Phase 4: the configuration probes (read only) --------
  always_comb begin : config_probes
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      cf_fp_use[s] = dut.u_bpu.r_val_p2 && dut.u_bpu.w_br_val_p2[s] &&
                     dut.u_bpu.w_fp_use_p2[s];
      cf_sc_hit[s] = dut.u_bpu.r_val_p3 && dut.u_bpu.w_sc_hit_p3[s];
      cf_tg_epoch[s] = dut.u_bpu.u_tage.u_tage_cntrl.lcl_epoch[s];
      cf_it_epoch[s] = dut.u_bpu.u_ittage.u_cntrl.lcl_epoch[s];
      for (int t = 1; t < TAGE_NUM_TABLES; t++)
        cf_tg_decay[s][t-1] =
          dut.u_bpu.u_tage.u_tage_cntrl.pred_val_p1[s] &&
          (dut.u_bpu.u_tage.u_tage_cntrl.ueff_p1[t][s] <
           dut.u_bpu.u_tage.u_tage_cntrl.t_use_p1[t][s]);
      for (int t = 1; t < IT_NUM_TABLES; t++)
        cf_it_decay[s][t-1] =
          dut.u_bpu.u_ittage.u_cntrl.pred_val_p1[s] &&
          (dut.u_bpu.u_ittage.u_cntrl.u_eff[t][s] <
           dut.u_bpu.u_ittage.u_cntrl.t_cntrl_bits_p1[t][s]
             [IT_MAX_CTR_WIDTH + IT_MAX_USE_WIDTH : IT_MAX_CTR_WIDTH + 1]);
    end
  end

  // ---- PERF-004 Phase 5: the SC decision probes (read only) ----------
  always_comb begin : sc_probes
    sd_idx  = dut.u_bpu.r_idx_p3;
    sd_thr  = 16'(dut.u_bpu.u_sc.u_sc_cntrl.threshold);
    sd_chi  = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.choose_hi_vlo));
    sd_cmed = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.choose_med_vvlo));
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      sd_hit[s]   = dut.u_bpu.r_val_p3 && dut.u_bpu.w_sc_hit_p3[s] &&
                    dut.u_bpu.r_slot_p3[s].slot_valid &&
                    (dut.u_bpu.r_slot_p3[s].br_type == COND);
      sd_pos[s]   = dut.u_bpu.r_slot_p3[s].pos;
      sd_p2tk[s]  = dut.u_bpu.r_taken_p3[s];
      sd_p3tk[s]  = dut.u_bpu.w_taken_p3[s];
      sd_hold[s]  = dut.u_bpu.r_lp_use_p3[s] | dut.u_bpu.r_fp_use_p3[s];
      sd_final[s] = dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_pred_tkn;
      sd_lcl[s]   = dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_lcl_pred_tkn;
      sd_ttkn[s]  = dut.u_bpu.u_sc.u_sc_cntrl.tage_meta_p3[s].tage_pred_tkn;
      sd_thi[s]   = dut.u_bpu.u_sc.u_sc_cntrl.tage_meta_p3[s]
                      .tage_pred_strong;
      sd_tmed[s]  = dut.u_bpu.u_sc.u_sc_cntrl.tage_meta_p3[s]
                      .tage_pred_medium;
      sd_sum[s]   = 16'(signed'(dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_sum));
    end
  end

  // ---- PERF-005 Phase 1: the decision probes (read only) -----------
  // The predictor modules' own outputs are read (perf.vlt keeps them out
  // of inlining), so an oracle force does not reach these values; the
  // cluster's own decisions (w_tage_hit_p2, w_fp_use_p2, w_sc_hit_p3)
  // are read where it forms them, and so is the RAS peek valid, which
  // selects the return's source.
  always_comb begin : decision_probes
    dp2_val   = dut.u_bpu.r_val_p2;
    dp2_idx   = dut.u_bpu.r_idx_p2;
    dp2_ftb   = dut.u_bpu.w_ftb_valid_p2;
    dp2_p1ret = dut.u_bpu.w_p1ret_any_p2;
    dp3_val   = dut.u_bpu.r_val_p3;
    dp3_idx   = dut.u_bpu.r_idx_p3;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      dp2_cond[s] = dut.u_bpu.w_br_val_p2[s] &&
                    (dut.u_bpu.w_br_type_p2[s] == COND);
      dp2_lp[s]   = dut.u_bpu.w_lp_use_p2[s];
      dp2_fp[s]   = dut.u_bpu.w_fp_use_p2[s];
      dp2_trdy[s] = dut.u_bpu.w_tage_pred_rdy_p2[s];
      dp2_thit[s] = dut.u_bpu.w_tage_hit_p2[s];
      dp2_prm[s]  = 3'(dut.u_bpu.u_tage.tage_pred_meta_p2[s].tage_prm_comp);
      dp2_alt[s]  = 3'(dut.u_bpu.u_tage.tage_pred_meta_p2[s].tage_alt_comp);
      dp2_usep[s] = dut.u_bpu.u_tage.tage_pred_meta_p2[s].tage_using_primary;
      dp2_irdy[s] = dut.u_bpu.w_ittage_pred_rdy_p2[s];
      dp2_ibid[s] = dut.u_bpu.u_ittage.ittage_pred_meta_p2[s].branch_id ==
                    dut.u_bpu.r_idx_p2;
      dp2_ihit[s] = dut.u_bpu.u_ittage.ittage_pred_meta_p2[s].ittage_hit;
      // PERF-005: the peek valid as the cluster reads it (bp_cluster
      // p2 return source, 1293-1296), forced under the oracle: the RAS
      // port read unforced made an oracle-forced RAS return r_other.
      dp2_pkv[s]  = dut.u_bpu.w_ras_peek_valid_p2[s];
      dp3_cond[s]  = dut.u_bpu.r_slot_p3[s].slot_valid &&
                     (dut.u_bpu.r_slot_p3[s].br_type == COND);
      dp3_schit[s] = dut.u_bpu.w_sc_hit_p3[s];
      dp3_hold[s]  = dut.u_bpu.r_lp_use_p3[s] | dut.u_bpu.r_fp_use_p3[s];
      dp3_p2tk[s]  = dut.u_bpu.r_slot_p3[s].taken;
      dp3_sctk[s]  = dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_pred_tkn;
      dp3_lcl[s]   = dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_lcl_pred_tkn;
      dp3_chs[s]   = 2'(dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_chooser);
      dp2_ttk[s]   = dut.u_bpu.w_tage_pred_meta_p2[s].tage_pred_tkn;
    end
  end

  // PERF-005 Phase 3: the TAGE probes.
  always_comb begin : tage_probes
    tl_q  = !dut.u_bpu.u_tage.u_tage_arb.pq_empty;
    tl_rb = dut.u_bpu.w_rollback_valid;
    tl_fh[0]  = 16'(dut.u_bpu.w_folded.tage_t1_idx_fh);
    tl_fh[1]  = 16'(dut.u_bpu.w_folded.tage_t1_tag_fh1);
    tl_fh[2]  = 16'(dut.u_bpu.w_folded.tage_t1_tag_fh2);
    tl_fh[3]  = 16'(dut.u_bpu.w_folded.tage_t2_idx_fh);
    tl_fh[4]  = 16'(dut.u_bpu.w_folded.tage_t2_tag_fh1);
    tl_fh[5]  = 16'(dut.u_bpu.w_folded.tage_t2_tag_fh2);
    tl_fh[6]  = 16'(dut.u_bpu.w_folded.tage_t3_idx_fh);
    tl_fh[7]  = 16'(dut.u_bpu.w_folded.tage_t3_tag_fh1);
    tl_fh[8]  = 16'(dut.u_bpu.w_folded.tage_t3_tag_fh2);
    tl_fh[9]  = 16'(dut.u_bpu.w_folded.tage_t4_idx_fh);
    tl_fh[10] = 16'(dut.u_bpu.w_folded.tage_t4_tag_fh1);
    tl_fh[11] = 16'(dut.u_bpu.w_folded.tage_t4_tag_fh2);
    hw_val = dut.u_bpu.w_ckpt_wr_en;
    hw_idx = dut.u_bpu.w_ckpt_wr_idx;
    hw_n   = 2'(dut.u_bpu.w_hist_num_branches);
    hw_tkn = 2'(dut.u_bpu.w_hist_pred_taken);
    hr_val  = dut.u_bpu.w_rollback_valid;
    hr_idx  = dut.u_bpu.w_rollback_ckpt_idx;
    hr_corr = dut.u_bpu.w_rb_corr;
    hr_n    = 2'(dut.u_bpu.w_rb_n);
    hr_tkn  = 2'(dut.u_bpu.w_rb_tkn);
    hp_ptr  = 16'(dut.u_bpu.u_bp_history.ghist_ptr_r);
    for (int i = 0; i < 16; i++)
      hp_win[i] = dut.u_bpu.u_bp_history.ghr_mem[
        (int'(dut.u_bpu.u_bp_history.ghist_ptr_r) - 1 - i + GHR_WIDTH)
        % GHR_WIDTH];
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      tl_val[s] = dut.u_bpu.u_tage.u_tage_arb.cntrl_pred_val_p0[s];
      tl_bid[s] = dut.u_bpu.u_tage.u_tage_arb.cntrl_pred_inp_p0[s].branch_id;
      tl_pc[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_pred_inp_p0[s].pc;
      tp_val[s] = dut.u_bpu.u_tage.u_tage_cntrl.pred_val_p1[s];
      for (int t = 0; t < 5; t++) begin
        tl_idx[t*NUM_PRED_SLOTS+s] = 16'(dut.u_bpu.u_tage.w_idx_p0[t][s]);
        tl_tag[t*NUM_PRED_SLOTS+s] = 16'(dut.u_bpu.u_tage.w_tag_p0[t][s]);
        tp_idx[t*NUM_PRED_SLOTS+s] =
          16'(dut.u_bpu.u_tage.u_tage_cntrl.t_idx_r1[t][s]);
        tp_tag[t*NUM_PRED_SLOTS+s] =
          16'(dut.u_bpu.u_tage.u_tage_cntrl.t_tag_r1[t][s]);
        tp_hit[t*NUM_PRED_SLOTS+s] = dut.u_bpu.u_tage.w_hit_p1[t][s];
        tp_cb[t*NUM_PRED_SLOTS+s]  =
          16'(dut.u_bpu.u_tage.w_cntrl_bits_p1[t][s]);
      end
      tu_uaon[s] = 4'(dut.u_bpu.u_tage.u_tage_cntrl.uaon[s]);
      tu_val[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_val_u0[s] &
                   dut.u_bpu.u_tage.u_tage_arb.trx_type;
      tu_bid[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.branch_id;
      tu_pidx[s] = 16'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_prm_idx);
      tu_aidx[s] = 16'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alt_idx);
      tu_cidx[s] = 16'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alc_idx);
      tu_ctag[s] = 8'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alc_tag);
      tu_pcmp[s] = 3'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_prm_comp);
      tu_acmp[s] = 3'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alt_comp);
      tu_ccmp[s] = 3'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alc_comp);
      tu_pctr[s] = 3'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_prm_ctr);
      tu_actr[s] = 3'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alt_ctr);
      tu_puse[s] = 2'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_prm_useful);
      tu_ause[s] = 2'(dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alt_useful);
      tu_ptk[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_prm_tkn;
      tu_atk[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_alt_tkn;
      tu_up[s]   = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_using_primary;
      tu_tk[s]   = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .tage_pred_meta.tage_pred_tkn;
      tu_res[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .resolved_taken;
      tu_mis[s]  = dut.u_bpu.u_tage.u_tage_arb.cntrl_upd_inp_u0[s]
                     .cond_mispredict;
      tu_ep[s]   = dut.u_bpu.u_tage.u_tage_cntrl.lcl_epoch[s];
    end
  end

  // PERF-005 Phase 3: the SC update probes.
  always_comb begin : sc_upd_probes
    su_thr    = 16'(dut.u_bpu.u_sc.u_sc_cntrl.threshold);
    su_thr_d  = 16'(dut.u_bpu.u_sc.u_sc_cntrl.threshold_d);
    su_tc     = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.tc_reg));
    su_tc_d   = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.tc_reg_d));
    su_chi_d  = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.choose_hi_vlo_d));
    su_cmed_d = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.choose_med_vvlo_d));
    su_wsel   = 1'(dut.u_bpu.u_sc.u_sc_cntrl.w_sel);
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      sd_ext[s] = 8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.tage_meta_p3[s]
                               .tage_extd_ctr));
      sd_ovr[s] = dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_override;
      sd_chs[s] = 2'(dut.u_bpu.u_sc.sc_pred_meta_p3[s].sc_chooser);
      su_val[s] = dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_val_u0[s];
      su_lcl[s] = dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                    .sc_lcl_pred_tkn;
      su_fin[s] = dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                    .sc_pred_tkn;
      su_ttk[s] = dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                    .sc_tage_pred_tkn;
      su_res[s] = dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].resolved_taken;
      su_wr[s]  = dut.u_bpu.u_sc.u_sc_cntrl.t_ctr_wr_u0[0][s];
      su_abs[s] = 16'(dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                        .sc_abs_sum);
      su_chs[s] = 2'(dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                       .sc_chooser);
      for (int t = 0; t < 5; t++) begin
        sd_ctr[t*NUM_PRED_SLOTS+s] =
          8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.t_ctr_p3[t][s]));
        su_ctr[t*NUM_PRED_SLOTS+s] =
          8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.sc_upd_inp_u0[s].sc_pred_meta
                       .sc_upd_ctr[t]));
        su_wd[t*NUM_PRED_SLOTS+s] =
          8'(signed'(dut.u_bpu.u_sc.u_sc_cntrl.t_ctr_wd_u0[t][s]));
      end
    end
  end
  for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_tw0
    assign tw_we[s]   = ~dut.u_bpu.u_tage.u_tage_bim.g_slot[s].ram_wen_n;
    assign tw_addr[s] = 16'(dut.u_bpu.u_tage.u_tage_bim.g_slot[s].ram_addr);
    assign tw_din[s]  = 16'(dut.u_bpu.u_tage.u_tage_bim.g_slot[s].ram_din);
    assign tw_bweb[s] =
      16'(dut.u_bpu.u_tage.u_tage_bim.g_slot[s].ram_bweb_n);
  end
  for (genvar t = 1; t < 5; t++) begin : g_tw
    for (genvar s = 0; s < NUM_PRED_SLOTS; s++) begin : g_tws
      assign tw_we[t*NUM_PRED_SLOTS+s] =
        ~dut.u_bpu.u_tage.gen_tage_tbl[t].u_tage_tbl.g_slot[s].ram_wen_n;
      assign tw_addr[t*NUM_PRED_SLOTS+s] =
        16'(dut.u_bpu.u_tage.gen_tage_tbl[t].u_tage_tbl.g_slot[s].ram_addr);
      assign tw_din[t*NUM_PRED_SLOTS+s] =
        16'(dut.u_bpu.u_tage.gen_tage_tbl[t].u_tage_tbl.g_slot[s].ram_din);
      assign tw_bweb[t*NUM_PRED_SLOTS+s] =
        16'(dut.u_bpu.u_tage.gen_tage_tbl[t].u_tage_tbl.g_slot[s]
            .ram_bweb_n);
    end
  end

  // PERF-005 Phase 2: the fast-path probes. The p2 set is the p1 set of
  // the cycle before (ftb_cntrl's p2 registers load every cycle).
  logic [FTB_IDX_BITS-1:0] fq_set_r;
  always_ff @(posedge clk) begin : fq_set_reg
    fq_set_r <= dut.u_bpu.u_ftb.u_ftb_cntrl.pred_set_idx_p1;
  end
  always_comb begin : fastpath_probes
    fq_val     = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_valid_p2;
    fq_set     = fq_set_r;
    fq_way     = dut.u_bpu.u_ftb.u_ftb_cntrl.q_way_p2;
    fq_bv[0]   = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_br0_valid_p2;
    fq_bv[1]   = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_br1_valid_p2;
    fq_pos[0]  = dut.u_bpu.u_ftb.u_ftb_cntrl.q_br0_pos;
    fq_pos[1]  = dut.u_bpu.u_ftb.u_ftb_cntrl.q_br1_pos;
    fq_conf[0] = dut.u_bpu.u_ftb.u_ftb_cntrl.q_br0_conf;
    fq_conf[1] = dut.u_bpu.u_ftb.u_ftb_cntrl.q_br1_conf;
    fq_fp      = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_fastpath_p2;
    fq_en      = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_fastpath_en;
    fu_val     = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_valid_u0;
    fu_set     = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_set_idx;
    fu_way     = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_way_u0;
    fu_hit     = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_hit;
    fu_isbr    = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_is_br_u0;
    fu_past    = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_past;
    fu_inpl    = dut.u_bpu.u_ftb.u_ftb_cntrl.inplace;
    fu_pos     = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_pos;
    fu_tkn     = dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_taken_u0;
    fu_oconf   = dut.u_bpu.u_ftb.u_ftb_cntrl.fld_old.conf;
    fu_nv[0]   = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br0.valid;
    fu_nv[1]   = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br1.valid;
    fu_npos[0] = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br0.pos;
    fu_npos[1] = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br1.pos;
    fu_nconf[0] = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br0.conf;
    fu_nconf[1] = dut.u_bpu.u_ftb.u_ftb_cntrl.upd_new.br1.conf;
    for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
      fs_acc[c]  = dut.u_ftq.u_ftb_sched.w_acc_ftb[c] &&
                   dut.u_ftq.u_ftb_sched.upd[c].is_br;
      fs_drop[c] = fs_acc[c]
        && !(!dut.u_ftq.u_ftb_sched.w_issue_from_skid
             && dut.u_ftq.u_ftb_sched.w_best_new[c])
        && !(dut.u_ftq.u_ftb_sched.skid_val
             ? dut.u_ftq.u_ftb_sched.w_best_new[c]
             : dut.u_ftq.u_ftb_sched.w_second_new[c]);
    end
  end

  // ---- the fetch record (PERF-003), by hierarchical reference ------
  always_comb begin : fetch_record
    fr_req_val   = dut.ftq_ifu_req_val;
    fr_req_rdy   = dut.ftq_ifu_req_rdy;
    fr_flush_val = dut.ftq_ifu_flush_val;
    fr_idx       = dut.ftq_ifu_idx;
    fr_rd_idx    = dut.u_ftq.u_entry.fetch_rd_idx;
    fr_start_pc  = dut.ftq_ifu_start_pc;
    fr_next_pc   = dut.ftq_ifu_next_pc;
    fr_taken_val = dut.ftq_ifu_taken_val;
    fr_taken_pos = dut.ftq_ifu_taken_pos;
    pc_val       = dut.u_ftq.u_ifu.pd_wr_val;
    pc_idx       = dut.u_ftq.u_ifu.pd_wr_idx;
    pc_succ      = dut.u_ftq.u_ifu.w_corr_succ;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      fr_s_val[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].slot_valid;
      fr_s_taken[s] = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].taken;
      fr_s_pos[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].pos;
      fr_s_type[s]  = 3'(dut.u_ftq.u_entry.fetch_rd_entry.slot[s].br_type);
      fr_s_src[s]   = 3'(dut.u_ftq.u_entry.fetch_rd_entry.slot[s].pred_src);
      fr_s_tgt[s]   = dut.u_ftq.u_entry.fetch_rd_entry.slot[s].target;
      pc_s_val[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].slot_valid;
      pc_s_taken[s] = dut.u_ftq.u_ifu.w_corr_slot[s].taken;
      pc_s_pos[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].pos;
      pc_s_type[s]  = 3'(dut.u_ftq.u_ifu.w_corr_slot[s].br_type);
      pc_s_src[s]   = 3'(dut.u_ftq.u_ifu.w_corr_slot[s].pred_src);
      pc_s_tgt[s]   = dut.u_ftq.u_ifu.w_corr_slot[s].target;
    end
    ew_alloc_val = dut.u_ftq.u_entry.alloc_wr_val;
    ew_alloc_idx = dut.u_ftq.u_entry.alloc_wr_idx;
    ew_p2_val    = dut.u_ftq.u_entry.p2_wr_val;
    ew_p2_idx    = dut.u_ftq.u_entry.p2_wr_idx;
    ew_p3_val    = dut.u_ftq.u_entry.p3_wr_val;
    ew_p3_idx    = dut.u_ftq.u_entry.p3_wr_idx;
    ew_alloc_pc  = dut.u_ftq.u_entry.alloc_wr_pc;
  end

  // ---- THE ORACLE (PERF-003, PF-11), by SV force inside bp_cluster ---
  // Every force is continuous, from the start, to a mux: the trace's
  // value where the gasket enables it (an entry allocated on the path,
  // at a slot the trace decides), else the predictor's own value. The
  // predictor's own value is read where the force does not reach:
  //   - r_ubtb_pred_p1 and r_ras_tos_*_p1 are bp_cluster's p0 -> p1
  //     registers, loaded every clock from w_ubtb_pred_p1 and
  //     w_ras_tos_*_p0 with a synchronous reset (bp_cluster stage_ff).
  //     sh_* below are the same registers, loaded from the same nets,
  //     so they hold the value the forced register would hold.
  //   - the p2 and p3 predictor outputs are read at the predictor
  //     module's own output port, a variable of its own because perf.vlt
  //     keeps loop_pred, ftb, tage, ittage, sc and ras out of inlining.
  //   - w_ftb_br_taken_p2 and _target_p2 are bp_cluster's per-slot
  //     views of the FTB's br0 and br1 ports; those ports are read.
  // Slot presence, type and position are never forced: a branch the
  // predictors hold in no slot stays a miss (PF-11).
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] sh_ubtb_pred;
  logic [VA_WIDTH-1:0]             sh_tos_addr [NUM_PRED_SLOTS];
  logic                            sh_tos_val  [NUM_PRED_SLOTS];
  always_ff @(posedge clk) begin : oracle_shadow
    if (!rstn) begin
      sh_ubtb_pred <= '0;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        sh_tos_addr[s] <= '0;
        sh_tos_val[s]  <= 1'b0;
      end
    end else begin
      sh_ubtb_pred <= dut.u_bpu.w_ubtb_pred_p1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        sh_tos_addr[s] <= dut.u_bpu.w_ras_tos_addr_p0[s];
        sh_tos_val[s]  <= dut.u_bpu.w_ras_tos_valid_p0[s];
      end
    end
  end

  logic [FTQ_IDX_BITS-1:0] pr_idx [3];
  always_comb begin : oracle_state
    os_p1_val = dut.u_bpu.r_val_p1;
    os_p1_pc  = dut.u_bpu.r_pc_p1;
    os_p1_idx = dut.u_bpu.r_idx_p1;
    os_p2_val = dut.u_bpu.r_val_p2;
    os_p2_pc  = dut.u_bpu.r_pc_p2;
    os_p2_idx = dut.u_bpu.r_idx_p2;
    os_p3_val = dut.u_bpu.r_val_p3;
    os_p3_pc  = dut.u_bpu.r_pc_p3;
    os_p3_idx = dut.u_bpu.r_idx_p3;
    pr_idx[0] = dut.u_bpu.r_idx_p1 - 1'b1;
    pr_idx[1] = dut.u_bpu.r_idx_p2 - 1'b1;
    pr_idx[2] = dut.u_bpu.r_idx_p3 - 1'b1;
    for (int g = 0; g < 3; g++) begin
      os_pr_pc[g]  = dut.u_ftq.u_entry.r_arr[pr_idx[g]].pc;
      os_pr_pft[g] = dut.u_ftq.u_entry.r_arr[pr_idx[g]].pft_addr;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        os_pr_s_val[g][s]   = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .slot_valid;
        os_pr_s_taken[g][s] = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .taken;
        os_pr_s_pos[g][s]   = dut.u_ftq.u_entry.r_arr[pr_idx[g]].slot[s]
                                .pos;
      end
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      os_p1_s_val[s]  = sh_ubtb_pred[s].valid;
      os_p1_s_pos[s]  = FTB_BR_POS_BITS'(sh_ubtb_pred[s].pos);
      os_p1_s_type[s] = 3'(sh_ubtb_pred[s].br_type);
      os_p2_s_val[s]  = dut.u_bpu.w_br_val_p2[s];
      os_p2_s_pos[s]  = dut.u_bpu.w_pos_p2[s];
      os_p2_s_type[s] = 3'(dut.u_bpu.w_br_type_p2[s]);
      os_p2_p1_s_val[s]  = dut.u_bpu.r_slot_p2[s].slot_valid;
      os_p2_p1_s_pos[s]  = dut.u_bpu.r_slot_p2[s].pos;
      os_p2_p1_s_type[s] = 3'(dut.u_bpu.r_slot_p2[s].br_type);
      os_p3_s_val[s]  = dut.u_bpu.r_slot_p3[s].slot_valid;
      os_p3_s_pos[s]  = dut.u_bpu.r_slot_p3[s].pos;
      os_p3_s_type[s] = 3'(dut.u_bpu.r_slot_p3[s].br_type);
    end
  end

  // The forced values. Each is a whole variable or array element, built
  // from the predictor's own value with the trace's fields put in: a
  // second force on another member of the same element is not applied
  // by this build (found here: of ITTAGE's prm_tgt and alt_tgt, only one
  // took), so no element is forced member by member.
  ubtb_pred_t [NUM_PRED_SLOTS-1:0] o_p1_ubtb;
  lp_pred_t             o_p1_lp   [NUM_PRED_SLOTS];
  logic                 o_p1_tosv [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p1_tosa [NUM_PRED_SLOTS];
  lp_pred_t             o_p2_lp   [NUM_PRED_SLOTS];
  tage_pred_meta_t      o_p2_tage [NUM_PRED_SLOTS];
  logic                 o_p2_ftk  [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_ftg  [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_ras  [NUM_PRED_SLOTS];
  // PERF-004: the RAS peek, the p2 target of an FTB return since BP-153
  // (bp_cluster p2 classification, p3_reach); before PERF-004 only the pop
  // was forced, so a return the trace takes off the RAS's top mispredicted
  // under the oracle (err_orc_slot_mispred).
  logic [VA_WIDTH-1:0]  o_p2_peek [NUM_PRED_SLOTS];
  logic                 o_p2_pkv  [NUM_PRED_SLOTS];
  ittage_pred_meta_t    o_p2_it   [NUM_PRED_SLOTS];
  logic [VA_WIDTH-1:0]  o_p2_jt;
  sc_pred_meta_t        o_p3_sc   [NUM_PRED_SLOTS];
  always_comb begin : oracle_values
    o_p1_ubtb = sh_ubtb_pred;
    o_p2_jt = (orc_on && orc_p2_jten) ? orc_p2_jtgt
                                      : dut.u_bpu.u_ftb.ftb_jmp_target_p2;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (orc_on && orc_p1_den[s]) o_p1_ubtb[s].br_taken = orc_p1_dir[s];
      if (orc_on && orc_p1_ten[s]) o_p1_ubtb[s].target   = orc_p1_tgt[s];
      o_p1_lp[s] = dut.u_bpu.u_loop_pred.pred_p1[s];
      if (orc_on && orc_p1_den[s]) o_p1_lp[s].lp_pred_taken = orc_p1_dir[s];
      o_p1_tosv[s] = (orc_on && orc_p1_ret[s]) ? orc_p1_dir[s]
                                               : sh_tos_val[s];
      o_p1_tosa[s] = (orc_on && orc_p1_ret[s]) ? orc_p1_tgt[s]
                                               : sh_tos_addr[s];
      o_p2_lp[s] = dut.u_bpu.u_loop_pred.pred_p2[s];
      if (orc_on && orc_p2_den[s]) o_p2_lp[s].lp_pred_taken = orc_p2_dir[s];
      o_p2_tage[s] = dut.u_bpu.u_tage.tage_pred_meta_p2[s];
      if (orc_on && orc_p2_den[s]) o_p2_tage[s].tage_pred_tkn = orc_p2_dir[s];
      o_p2_ftk[s]  = (orc_on && orc_p2_den[s])
                   ? orc_p2_dir[s]
                   : ((s == 0) ? dut.u_bpu.u_ftb.ftb_br0_taken_p2
                               : dut.u_bpu.u_ftb.ftb_br1_taken_p2);
      o_p2_ftg[s]  = (orc_on && orc_p2_ten[s])
                   ? orc_p2_tgt[s]
                   : ((s == 0) ? dut.u_bpu.u_ftb.ftb_br0_target_p2
                               : dut.u_bpu.u_ftb.ftb_br1_target_p2);
      o_p2_ras[s]  = (orc_on && orc_p2_ten[s])
                   ? orc_p2_tgt[s]
                   : dut.u_bpu.u_ras.ras_pop_addr_p2[s];
      o_p2_peek[s] = (orc_on && orc_p2_ten[s])
                   ? orc_p2_tgt[s]
                   : dut.u_bpu.u_ras.ras_peek_addr_p2[s];
      o_p2_pkv[s]  = (orc_on && orc_p2_ten[s])
                   ? 1'b1
                   : dut.u_bpu.u_ras.ras_peek_valid_p2[s];
      o_p2_it[s] = dut.u_bpu.u_ittage.ittage_pred_meta_p2[s];
      if (orc_on && orc_p2_ten[s]) begin
        o_p2_it[s].ittage_prm_tgt = orc_p2_tgt[s][VA_WIDTH-1:1];
        o_p2_it[s].ittage_alt_tgt = orc_p2_tgt[s][VA_WIDTH-1:1];
      end
      o_p3_sc[s] = dut.u_bpu.u_sc.sc_pred_meta_p3[s];
      if (orc_on && orc_p3_den[s]) o_p3_sc[s].sc_pred_tkn = orc_p3_dir[s];
    end
  end

  // The forces: the predictor outputs the stage logic reads, by slot.
  //   p1 (p1_form_comb): r_ubtb_pred_p1 (.br_taken, .target), the loop
  //      predictor's pred_p1 (.lp_pred_taken), the RAS top of stack
  //      r_ras_tos_val_p1 and r_ras_tos_addr_p1
  //   p2 (p2_class_comb, p2_succ_comb): w_lp_pred_p2 (.lp_pred_taken),
  //      w_tage_pred_meta_p2 (.tage_pred_tkn), the FTB br direction and
  //      target w_ftb_br_taken_p2 and _target_p2, the FTB jump target
  //      w_ftb_jmp_target_p2, the RAS pop address w_ras_pop_addr_p2 and
  //      (PERF-004) its peek, w_ras_peek_addr_p2 and _valid_p2,
  //      w_ittage_pred_meta_p2 (.ittage_prm_tgt, .ittage_alt_tgt)
  //   p3 (p3_redir_comb, p3_slot_comb): w_sc_pred_meta_p3 (.sc_pred_tkn)
  initial begin : oracle_p1_ubtb
    force dut.u_bpu.r_ubtb_pred_p1 = o_p1_ubtb;
  end
  for (genvar gs = 0; gs < NUM_PRED_SLOTS; gs++) begin : g_oracle
    initial begin
      force dut.u_bpu.w_lp_pred_p1[gs]          = o_p1_lp[gs];
      force dut.u_bpu.r_ras_tos_val_p1[gs]      = o_p1_tosv[gs];
      force dut.u_bpu.r_ras_tos_addr_p1[gs]     = o_p1_tosa[gs];
      force dut.u_bpu.w_lp_pred_p2[gs]          = o_p2_lp[gs];
      force dut.u_bpu.w_tage_pred_meta_p2[gs]   = o_p2_tage[gs];
      force dut.u_bpu.w_ftb_br_taken_p2[gs]     = o_p2_ftk[gs];
      force dut.u_bpu.w_ftb_br_target_p2[gs]    = o_p2_ftg[gs];
      force dut.u_bpu.w_ras_pop_addr_p2[gs]     = o_p2_ras[gs];
      force dut.u_bpu.w_ras_peek_addr_p2[gs]    = o_p2_peek[gs];   // PERF-004
      force dut.u_bpu.w_ras_peek_valid_p2[gs]   = o_p2_pkv[gs];
      force dut.u_bpu.w_ittage_pred_meta_p2[gs] = o_p2_it[gs];
      force dut.u_bpu.w_sc_pred_meta_p3[gs]     = o_p3_sc[gs];
    end
  end
  initial begin : oracle_jump
    force dut.u_bpu.w_ftb_jmp_target_p2 = o_p2_jt;
  end

  // ---- THE RAS CLASSIFICATION (BP-151), by hierarchical reference ----
  // Read only: nothing here drives the design. The RAS is not inlined
  // (perf.vlt), so its ports and internal variables are its own.
  always_comb begin : ras_class
    rc_tosr   = dut.u_bpu.u_ras.tosr;
    rc_tosw   = dut.u_bpu.u_ras.tosw;
    rc_bos    = dut.u_bpu.u_ras.bos;
    rc_csp    = dut.u_bpu.u_ras.csp;
    rc_ccnt   = dut.u_bpu.u_ras.c_cnt;
    for (int i = 0; i < RAS_SPEC_ENTRIES; i++) begin
      rc_spec_addr[i] = dut.u_bpu.u_ras.spec_ret_addr[i];
      rc_spec_nos[i]  = dut.u_bpu.u_ras.spec_nos[i];
      rc_spec_rctr[i] = dut.u_bpu.u_ras.spec_rctr[i];
      rc_spec_bot[i]  = dut.u_bpu.u_ras.spec_bot[i];
    end
    for (int i = 0; i < RAS_COMMIT_ENTRIES; i++) begin
      rc_cmt_addr[i] = dut.u_bpu.u_ras.commit_ret_addr[i];
    end
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      rc_p2_val[s]       = dut.u_bpu.u_ras.ras_pred_val_p2[s];
      rc_p2_type[s]      = 3'(dut.u_bpu.u_ras.ras_br_type_p2[s]);
      rc_p2_ft[s]        = dut.u_bpu.u_ras.ras_fall_through_p2[s];
      rc_p2_popv[s]      = dut.u_bpu.u_ras.ras_pop_valid_p2[s];
      rc_p2_popa[s]      = dut.u_bpu.u_ras.ras_pop_addr_p2[s];
      rc_p2_op[s]        = dut.u_bpu.u_ras.p2_op[s];
      rc_p2_inc[s]       = dut.u_bpu.u_ras.p2_push_inc[s];
      rc_p2_sat[s]       = dut.u_bpu.u_ras.p2_push_sat[s];
      rc_p2_pre[s]       = dut.u_bpu.u_ras.p2_pre_tosr[s];
      rc_p2_pre_empty[s] = dut.u_bpu.u_ras.p2_pre_empty[s];
      rc_p3_val[s]       = dut.u_bpu.u_ras.ras_pred_val_p3[s];
      rc_p3_type[s]      = 3'(dut.u_bpu.u_ras.ras_br_type_p3[s]);
      rc_p3_op[s]        = dut.u_bpu.u_ras.p3_op_q[s];
      rc_p3_ft[s]        = dut.u_bpu.u_ras.p3_fallthr_q[s];
    end
    for (int p = 0; p < 4 * NUM_PRED_SLOTS; p++) begin
      rc_we[p]    = dut.u_bpu.u_ras.sp_we[p];
      rc_waddr[p] = dut.u_bpu.u_ras.sp_waddr[p];
    end
    rc_keep    = dut.u_bpu.u_ras.ras_p2_keep;
    rc_ftb_p2  = dut.u_bpu.w_ftb_valid_p2;
    rc_rs_val  = dut.u_bpu.u_ras.ras_restore_val;
    rc_rs_tosr = dut.u_bpu.u_ras.ras_restore_snapshot.tosr;
    rc_rs_tosw = dut.u_bpu.u_ras.ras_restore_snapshot.tosw;
    rc_rs_bos  = dut.u_bpu.u_ras.ras_restore_snapshot.bos;
    rc_cm_val  = dut.u_bpu.u_ras.ras_commit_val;
    rc_cm_type = 3'(dut.u_bpu.u_ras.ras_commit_br_type);
    rc_cm_addr = dut.u_bpu.u_ras.ras_commit_ret_addr;
    rc_cm_tosr = dut.u_bpu.u_ras.ras_commit_snapshot.tosr;
    rc_cm_bos  = dut.u_bpu.u_ras.ras_commit_snapshot.bos;
    rc_cm_idx  = dut.u_ftq.u_entry.commit_rd_idx;
    rc_rs_idx  = dut.u_ftq.ftq_rollback_idx;
    rc_pd_pos  = dut.u_ftq.u_ifu.ifu_ftq_mis_pos;
    // BP-152.
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      rc_p2_fbi[s] = dut.u_bpu.u_ras.p2_fb_idx[s];
      rc_p2_dep[s] = dut.u_bpu.u_ras.ras_snapshot_p2[s].dep;
    end
    rc_dcm      = dut.u_bpu.u_ras.dcm;
    rc_rs_undo  = dut.u_bpu.u_ras.ras_rs_undo;
    // BP-153: an undo of the block's pop with a pop record to undo.
    rc_rs_undo_pop = dut.u_bpu.u_ras.ras_rs_undo_pop &&
                     (dut.u_bpu.u_ras.ras_restore_snapshot.pmode !=
                      RAS_POP_NONE);
    rc_pd_val   = dut.u_bpu.u_ras.ras_pd_val;
    rc_pd_type  = 3'(dut.u_bpu.u_ras.ras_pd_br_type);
    rc_pd_ret   = dut.u_bpu.u_ras.ras_pd_ret_addr;
    // The C1 push is restore port 4 since BP-153 (RS_P_PUSH; 3 before).
    rc_pd_al    = dut.u_bpu.u_ras.rs_we[4] && dut.u_bpu.u_ras.rs_al[4];
    rc_pd_waddr = dut.u_bpu.u_ras.rs_waddr[4];
  end

endmodule : perf_top
