// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// Testbench for fe_top (BP-118 Problem 8, BP-119). The front end runs
// programs end to end against models of everything outside its
// boundary (fe_decisions.md FE-17, FE-20):
//
//   memory    one byte array. It answers the L1I's l2-side TileLink
//             link (Get, two 256-bit AccessAckData beats per 64-byte
//             line) and the page table walker's memory port (8-byte
//             READ and CAS, ptw_mem_interfaces.md) from the one image
//             (WM-10), with a PTE change before a CAS (WM-11), an error
//             on a chosen access (WM-12) and variable ready and latency
//             (WM-13)
//   walker    BP-123: the RTL page table walker, rtl/mmu/ptw,
//             instantiated beside the front-end top (MMU-1a) and
//             connected on the itlb_l2t_* group; its CSR group is driven
//             here (MMU-24a). This was a behavioural Sv39 walk with a
//             fixed latency
//   backend   takes decode's output whenever the ibuf presents it,
//             compares it in order against the program's executed
//             stream, resolves every control transfer it retires,
//             redirects on a mispredict (RC_MISPREDICT, _self clear)
//             and on an ecall or a fetch fault (RC_TRAP, _self set,
//             to the program's handler), and commits by watermark
//
// THE EXECUTED STREAM IS BUILT BY THE PROGRAM WRITER, not computed by
// an instruction-set model. Every instruction is written into memory
// and, when it lies on the path the program takes, appended to the
// expected stream with its PC, its 32-bit (expanded) encoding, its
// length, its branch type, the next PC and, for a trap or a fault,
// the handler. Conditions are constant (beq x0,x0 is always taken,
// bne x0,x0 never), and a return's target is the call's link, which
// the writer knows. So no register file is modelled.
//
// WHAT A RETIRED INSTRUCTION IS CHECKED FOR: its PC is the next
// expected one; is_rvc; the expanded instruction; decode raises no
// illegal; the fault cause and faulting VA when one is expected; and
// its FTQ index and position name the block the FTQ fetched for it:
// the start PC the FTQ presented on its fetch port for that index,
// plus two bytes per position, is the instruction's PC.
//
// NOTHING EXTRA, NOTHING MISSING. A delivered PC that is not the next
// expected one is legal only right after a retired conditional branch
// or return: the front end predicted its direction or target wrongly
// and the backend redirects. Not after a JAL: predecode truncates the
// bundle at one (M1, M3, IB-2), so a JAL's successor is its target. A
// mismatch anywhere else is a stream error, a duplicated, skipped or
// invented instruction, and fails the run.
//
// BP-119. Every update path is connected (TD#151), so the predictors
// train. Two programs are added: loops (nested counted loops with a
// conditional, an indirect jump and an indirect call in the body, so
// the uBTB, LP, TAGE, SC and ITTAGE all receive updates and then
// predict trained) and coro (two coroutines switching by return-call,
// jalr x1, 0(x5) and jalr x5, 0(x1), TD#152, in a loop). A loop is
// written to memory once and its execution appended to the expected
// stream once per iteration (rep_iter); the loop branch's direction
// per iteration is known to the writer, as every other outcome is.
// Each program reports, per predictor, the cycles in which it received
// an update at the cluster (the valids after the cluster's own type
// and ready gates), and the backend mispredict, predecode redirect and
// p2 / p3 BPU redirect counts.
//
// BP-120. A fifth program, calls: main calls f, f calls g then h in
// sequence and returns, in a loop (TD#159, the RAS link). Each program
// also reports its RAS mispredicts (backend mispredicts of a RETURN or
// RETURN_CALL) and how often the FTB jump field was trained by a jump
// at a different position from the stored one (TD#156: two jumps of
// one region taking turns in the one field).
//
// BP-121. Programs covering every predictor path the planning
// documents describe (the program list is in run_prog below). One
// program runs per simulation, named by +PROG=<name>; each is its own
// regression target. BP-122 removed the mode that ran every program in
// one simulation without +PROG: the predictor tables carried from one
// program into the next, so the counts of every program after the
// first depended on the order. sim_fe_top runs each program in its own
// simulation. Every count
// stops at the last retirement (TD#167): the 200-cycle drain after it
// is not measured. Each program reports its cycles, its mispredicts,
// the mispredicts after warm-up by branch type and by PC (a program
// sets warm_e, the first expected entry after warm-up), and per
// predictor the updates it received and the predictions of it the FTQ
// used. THE RAS COMMIT IS CHECKED against the executed stream: every
// retired call, return and return-call is queued with its link
// address, and each ras_commit the cluster performs must be the next
// one, in order, with the same type and, for a push, the same address.
// A loop body whose path differs per iteration is emitted once per
// iteration by the same emitter calls; re-emitting rewrites the same
// bytes, and dry mode writes memory without appending to the stream.
// +define+BASE_RTL compiles this file against the tree as BP-121
// received it (no ftq_resolve_t.is_rvc, no ftb_cntrl upd_hit, no
// corrected-history nets), for the before column of its measurements.
//
// BP-123. Programs for maintenance (fencei, cboinval), uncached fetch
// (uc_nc, uc_io), the walker (pt_*) and the RVA23 extensions that reach
// fetch and decode (zstar). The backend model gained: memory patches a
// store applies when it retires (self-modifying code); the commit
// stage's FENCE.I / cbo.inval handshake, holding the restart until the
// IFU's ack (l1i_ifu_interfaces.md 11, A1); a CSR write that changes
// the walker's envcfg bits and restarts; the GPA and its kind on a
// guest-page fault; decode's operation and predecode's class per
// instruction where a program names them; and an EAGER commit mode for
// the uncached programs, which commits the entry of the last retired
// instruction as soon as nothing is in flight to the backend and
// resolves a block-ending branch against the block the FTQ fetched after
// it. Every program checks, every cycle, that no uncached request is
// presented before every older instruction has committed or off the
// path, that no uncached line is written into the L1I, and that an
// uncached instruction is delivered alone.
//
// BP-134. Program rec_undo: a recursion whose return blocks put a
// conditional before the ret, so SC reversing it at p3 undoes a pop
// that decremented a recursion count (TD#78). It counts those undos
// and checks each put the count back.
//
// BP-135. Program t0_uaon: T0 chosen as the TAGE provider by
// use_alt_on_na over a tagged primary, and then updated (CTR rows
// 19.1-19.8, BP-133). It counts those updates by row and checks each
// T0 write.
//
// BP-137. Program init_walk: the loops stream run without the fast-init
// plusargs (its own target), so the TAGE, ITTAGE and SC init walks run.
// It checks that the first p0 request follows the last init ready and
// that no predictor answers or trains before its own ready.
//
// DOC-001. The models -- the DUT and walker hookup, the program
// writer, the memory model, the backend and the CSR setup -- are in
// models/ (fe_demo_tb_decisions.md FDT-4), shared with the
// front-end demonstration testbench, examples/fe_demo. Each is
// included below where its text stood. This file keeps the
// predictor observation, the per-cycle uncached checks, the
// report and the programs.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;
import decode_pkg::*;
import csr_pkg::*;

module tb;

  `include "fe_tb_dut.svh"

  // ---- bookkeeping ----------------------------------------------------
  int    pass_cnt;
  int    fail_cnt;

  task automatic chk(input string nm, input logic ok);
    if (ok) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL: [%s] %s", tname, nm);
    end
  endtask

  `include "fe_tb_writer.svh"

  `include "fe_tb_mem.svh"

  `include "fe_tb_be_state.svh"

  // =================================================================
  // BP-119: what the predictors received, and the BPU redirects. The
  // counts are the valids AFTER the cluster's own gates (type and
  // queue ready), i.e. updates the predictor accepted, one per slot
  // per cycle.
  // =================================================================
  int n_u_ubtb;
  int n_u_lp;
  int n_u_tage;
  int n_u_ittage;
  int n_u_sc;
  int n_u_ras;
  int n_rc_p2;
  int n_rc_commit;
  int n_redir_p2;
  int n_redir_p3;
  int n_nomap;
  int n_plc_occ;
  int n_plc_tbl;
  int n_jmp_swap;
  // BP-121: predictions the FTQ used, per predictor. Each counts the
  // slots (or blocks) of a group the FTQ accepted (the shadow's ok_*,
  // so a group for a squashed entry is not counted) whose recorded
  // source is that predictor:
  //   uBTB    p1 blocks the uBTB hit
  //   LP      p1 slots whose direction the LP supplied, and (BP-122)
  //           p2 slots whose direction the LP supplied (n_use_lp2),
  //           the direction the entry keeps: SC does not override it
  //   FTB     p2 groups the FTB answered (bpu_slot_val_p2)
  //   TAGE    p2 conditional slots whose direction TAGE supplied
  //   SC      p3 conditional slots SC answered (n_use_sc), and those
  //           whose direction SC changed (n_sc_flip)
  //   ITTAGE  p2 indirect slots whose target ITTAGE supplied
  //   RAS     p1 and p2 return slots whose target the RAS supplied
  int n_use_ubtb;
  int n_use_lp;
  // BP-122: p2 conditional slots whose direction the loop predictor
  // supplied (the LP wins at p2 and p3 when trusted, ruled by Jeff).
  int n_use_lp2;
  int n_use_ftb;
  int n_use_tage;
  int n_use_sc;
  int n_sc_flip;
  int n_use_ittage;
  int n_use_ras;
  int n_u_ftb;
  // BP-121: responses of the queued predictors at the stage the
  // cluster reads them, for the p2 (TAGE, ITTAGE) or p3 (SC) block:
  // on time (branch_id is the block's) or late (an older block's).
  int n_tage_ok;
  int n_tage_late;
  int n_it_ok;
  int n_it_late;
  int n_sc_ok;
  int n_sc_late;

  // BP-121: p2 blocks whose history bundle (the branches on the path
  // and their directions) differs from the bundle p1 wrote, with no p2
  // redirect to correct it; and p2 redirects.
  // BP-129: one direction bit per predicted branch, NUM_PRED_SLOTS
  // bits, and a count of 0 to NUM_PRED_SLOTS. A direction is compared
  // only below the count (nb_mask).
  int                        n_hist_mis;
  logic [PRED_CNT_BITS-1:0]  p1_nb  [0:FTQ_DEPTH-1];
  logic [NUM_PRED_SLOTS-1:0] p1_tkn [0:FTQ_DEPTH-1];

  function automatic logic [NUM_PRED_SLOTS-1:0] nb_mask(
    input logic [PRED_CNT_BITS-1:0] n);
    logic [NUM_PRED_SLOTS-1:0] m;
    for (int b = 0; b < NUM_PRED_SLOTS; b++) m[b] = (b < int'(n));
    return m;
  endfunction

  always @(posedge clk) begin : hist_log
    if (rstn && dut.u_bpu.r_val_p1) begin
      p1_nb[dut.u_bpu.r_idx_p1]  <= dut.u_bpu.w_hist_num_branches;
      p1_tkn[dut.u_bpu.r_idx_p1] <= dut.u_bpu.w_hist_pred_taken &
                                    nb_mask(dut.u_bpu.w_hist_num_branches);
    end
`ifndef BASE_RTL
    if (meas && dut.u_bpu.r_val_p2 && dut.u_ftq.w_ok_blk_p2 &&
        dut.u_bpu.w_ftb_valid_p2 && !dut.u_bpu.w_any_redir_p2 &&
        ((p1_nb[dut.u_bpu.r_idx_p2] != dut.u_bpu.w_c2_n) ||
         (p1_tkn[dut.u_bpu.r_idx_p2] != (dut.u_bpu.w_c2_tkn &
            nb_mask(dut.u_bpu.w_c2_n)))))
      n_hist_mis <= n_hist_mis + 1;
`endif
  end

  // BP-121, TD#161: a p3 slot write for an entry whose p2 slot group
  // was not written this allocation (the FTB did not answer it), which
  // overwrote the p1 slots with an empty view. Per index, whether the
  // p2 group was written since the entry's p1 allocation.
  logic p2_wr_seen [0:FTQ_DEPTH-1];
  int   n_p3_no_p2;
  always @(posedge clk) begin : p3_log
    if (rstn && dut.u_ftq.w_ok_pred_p1) p2_wr_seen[dut.bpu_pred_idx_p1] <= 1'b0;
    if (rstn && dut.u_ftq.w_ok_slot_p2) p2_wr_seen[dut.bpu_slot_idx_p2] <= 1'b1;
    if (meas && dut.u_ftq.w_ok_slot_p3 && !p2_wr_seen[dut.bpu_slot_idx_p3])
      n_p3_no_p2 <= n_p3_no_p2 + 1;
  end

  // BP-121: the cluster's own p2 redirect keeps the redirecting block's
  // RAS operation (the restore is not applied to it). The cycle after a
  // p2 redirect the FTQ took for a block that operated on the RAS, the
  // RAS top must be the block's post-op snapshot (bpu_blk_ras_p2).
  logic                    own_chk;
  logic [RAS_PTR_BITS-1:0] own_tosr;
  int                      n_own_ok;
  int                      n_own_bad;
  always @(posedge clk) begin : own_log
    if (rstn && own_chk) begin
      if (dut.u_bpu.u_ras.tosr == own_tosr) n_own_ok  <= n_own_ok + 1;
      else                                  n_own_bad <= n_own_bad + 1;
    end
`ifndef BASE_RTL
    // Any slot operated on the RAS (BP-128: the OR of slots 0 and 1).
    own_chk  <= rstn && meas && dut.u_bpu.w_own_p2 &&
                dut.u_bpu.w_ras_pred_val_p2.or();
`else
    own_chk  <= rstn && meas && dut.u_ftq.w_arm_win[4] &&
                (dut.u_bpu.w_ras_pred_val_p2[0] ||
                 dut.u_bpu.w_ras_pred_val_p2[1]);
`endif
    own_tosr <= dut.bpu_blk_ras_p2.tosr;
  end

  // BP-121, TD#149 measured: p3 repairs (the p3 RAS view of a block
  // differs from its p2 operation), and backend restores that name an
  // entry a p3 repair changed (its snapshot, written at p2, predates
  // the repair).
  logic p3_rep [0:FTQ_DEPTH-1];
  int   n_p3_rep;
  int   n_rest_rep;
  always @(posedge clk) begin : rep_log
    logic rep;   // some slot's p3 RAS view differs from its p2 one
    if (rstn && dut.u_ftq.w_ok_pred_p1) p3_rep[dut.bpu_pred_idx_p1] <= 1'b0;
`ifndef BASE_RTL
    // Over every slot (BP-128: slots 0 and 1 written out).
    rep = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++)
      rep = rep ||
            ((dut.u_bpu.w_ras_pred_val_p3[s] != dut.u_bpu.r_ras_val_p3[s]) &&
             (dut.u_bpu.w_ras_br_type_p3[s] inside {DIRECT_CALL, INDIRECT_CALL,
                                                    RETURN, RETURN_CALL}));
    if (rstn && dut.u_bpu.r_val_p3 && rep) begin
      p3_rep[dut.u_bpu.r_idx_p3] <= 1'b1;
      if (meas) n_p3_rep <= n_p3_rep + 1;
    end
`endif
    if (meas && dut.u_ftq.w_arm_win[1] && dut.ras_restore_val &&
        p3_rep[dut.ftq_rollback_idx])
      n_rest_rep <= n_rest_rep + 1;
  end

  // BP-134: p3 undos of a pop that decremented a recursion count
  // (TD#78), and whether each put the count back. An event is a slot
  // whose registered p2 op (ras.sv p3_op_q) pops over a pop that held
  // TOSR (p3_pop_dec_q), whose p3 view has no pop, in a cycle with no
  // RAS restore (which drops the repair). The expected count is taken
  // from the array before the undo's edge, plus one; it is compared
  // after the edge. Only an undo in a cycle whose p2 pass is dropped
  // (ras_p2_keep low, the p3 redirect the reversal makes) is compared,
  // so no p2 write can touch the entry in the same edge.
  int                        n_undo_rdec;
  int                        n_undo_ok;
  int                        n_undo_bad;
  logic                      ud_pend [0:NUM_PRED_SLOTS-1];
  logic [RAS_PTR_BITS-1:0]   ud_idx  [0:NUM_PRED_SLOTS-1];
  logic [RAS_RCTR_WIDTH-1:0] ud_exp  [0:NUM_PRED_SLOTS-1];
  always @(posedge clk) begin : undo_rdec_log
`ifndef BASE_RTL
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (rstn && ud_pend[s]) begin
        if (dut.u_bpu.u_ras.spec_rctr[ud_idx[s]] == ud_exp[s])
          n_undo_ok <= n_undo_ok + 1;
        else
          n_undo_bad <= n_undo_bad + 1;
      end
      ud_pend[s] <= 1'b0;
      if (meas && dut.u_bpu.u_ras.ras_rst_done &&
          !dut.u_bpu.u_ras.ras_restore_val &&
          dut.u_bpu.u_ras.p3_op_q[s][1] && dut.u_bpu.u_ras.p3_pop_dec_q[s] &&
          !(dut.u_bpu.u_ras.ras_pred_val_p3[s] &&
            (dut.u_bpu.u_ras.ras_br_type_p3[s] inside {RETURN, RETURN_CALL})))
      begin
        n_undo_rdec <= n_undo_rdec + 1;
        if (!dut.u_bpu.u_ras.ras_p2_keep) begin
          ud_pend[s] <= 1'b1;
          ud_idx[s]  <= dut.u_bpu.u_ras.p3_pre_tosr_q[s];
          ud_exp[s]  <= dut.u_bpu.u_ras.spec_rctr[
                          dut.u_bpu.u_ras.p3_pre_tosr_q[s]]
                        + RAS_RCTR_WIDTH'(1);
        end
      end
    end
`endif
  end

  // BP-135: TAGE updates of T0 as the provider through use_alt_on_na
  // (tage_cntrl_ctr_update_rules.md rows 19.1-19.8, BP-133). An event
  // is an update tage_cntrl applies (its update valid in a cycle the
  // arbiter grants to updates, trx_type) whose meta has a tagged
  // primary, the alternate T0 and tage_using_primary 0. The T0 entry
  // it writes is slot s's copy of the T0 RAM (tage_bim keeps one per
  // slot) at the meta's alternate index. The expected value is derived
  // here from the meta: its T0 counter (tage_alt_ctr, the 2b value
  // zero-padded) stepped toward resolved_taken, saturating. It is
  // compared after the edge; one T0 write per slot per edge, so no
  // other write can touch the entry in that edge. Also counted: the p2
  // predictions that selected T0 this way, the row of each update, and
  // the highest use_alt_on_na counter value per slot.
  int                         n_t0u_pred;
  int                         n_t0u_upd;
  int                         n_t0u_ok;
  int                         n_t0u_bad;
  int                         n_t0u_row [1:8];
  int                         uaon_max  [0:NUM_PRED_SLOTS-1];
  logic                       t0u_pend  [0:NUM_PRED_SLOTS-1];
  logic [TAGE_TBL_IDX[0]-1:0] t0u_idx   [0:NUM_PRED_SLOTS-1];
  logic [TAGE_TBL_CTR[0]-1:0] t0u_exp   [0:NUM_PRED_SLOTS-1];

  // The row of rows 19.1-19.8 an update is, from its meta and outcome.
  // UP is 0 and PT is aT in all eight; pT, aT and RT name the row.
  function automatic int t0u_row_of(input logic pt, input logic at,
                                    input logic rt);
    case ({pt, at, rt})
      3'b011:  return 1;
      3'b111:  return 2;
      3'b000:  return 3;
      3'b100:  return 4;
      3'b010:  return 5;
      3'b101:  return 6;
      3'b110:  return 7;
      default: return 8;   // 3'b001
    endcase
  endfunction

  always @(posedge clk) begin : t0_uaon_log
    logic [TAGE_TBL_CTR[0]-1:0] t0u_old;
    logic [TAGE_TBL_CTR[0]-1:0] t0u_got;
    tage_upd_inp_t              t0u_u;
    tage_pred_meta_t            t0u_m;
`ifndef BASE_RTL
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (rstn && t0u_pend[s]) begin
        t0u_got = (s == 0)
          ? dut.u_bpu.u_tage.u_tage_bim.g_slot[0].u_ram.mem
              [t0u_idx[s][TAGE_TBL_IDX[0]-1]][t0u_idx[s][TAGE_TBL_IDX[0]-2:0]]
          : dut.u_bpu.u_tage.u_tage_bim.g_slot[NUM_PRED_SLOTS-1].u_ram.mem
              [t0u_idx[s][TAGE_TBL_IDX[0]-1]][t0u_idx[s][TAGE_TBL_IDX[0]-2:0]];
        if (t0u_got == t0u_exp[s]) n_t0u_ok  <= n_t0u_ok + 1;
        else                       n_t0u_bad <= n_t0u_bad + 1;
      end
      t0u_pend[s] <= 1'b0;
      if (meas && int'(dut.u_bpu.u_tage.u_tage_cntrl.uaon[s]) > uaon_max[s])
        uaon_max[s] <= int'(dut.u_bpu.u_tage.u_tage_cntrl.uaon[s]);
      t0u_m = dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_meta_p2[s];
      if (meas && dut.u_bpu.u_tage.u_tage_cntrl.tage_pred_rdy_p2[s] &&
          !t0u_m.tage_using_primary && (t0u_m.tage_prm_comp != '0) &&
          (t0u_m.tage_alt_comp == '0))
        n_t0u_pred <= n_t0u_pred + 1;
      t0u_u = dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_inp_u0[s];
      if (meas && dut.u_bpu.u_tage.u_tage_cntrl.trx_type &&
          dut.u_bpu.u_tage.u_tage_cntrl.tage_upd_val_u0[s] &&
          !t0u_u.tage_pred_meta.tage_using_primary &&
          (t0u_u.tage_pred_meta.tage_prm_comp != '0) &&
          (t0u_u.tage_pred_meta.tage_alt_comp == '0)) begin
        n_t0u_upd <= n_t0u_upd + 1;
        n_t0u_row[t0u_row_of(t0u_u.tage_pred_meta.tage_prm_tkn,
                             t0u_u.tage_pred_meta.tage_alt_tkn,
                             t0u_u.resolved_taken)] <=
          n_t0u_row[t0u_row_of(t0u_u.tage_pred_meta.tage_prm_tkn,
                               t0u_u.tage_pred_meta.tage_alt_tkn,
                               t0u_u.resolved_taken)] + 1;
        t0u_old     = t0u_u.tage_pred_meta.tage_alt_ctr[TAGE_TBL_CTR[0]-1:0];
        t0u_pend[s] <= 1'b1;
        t0u_idx[s]  <= t0u_u.tage_pred_meta.tage_alt_idx[TAGE_TBL_IDX[0]-1:0];
        t0u_exp[s]  <= t0u_u.resolved_taken
          ? ((t0u_old == '1) ? t0u_old : t0u_old + 1'b1)
          : ((t0u_old == '0) ? t0u_old : t0u_old - 1'b1);
      end
    end
`endif
  end

  // BP-122 (ruled by Jeff: the LP wins at p2 and p3): a slot whose p2
  // direction the loop predictor supplied keeps it at p3. Per index,
  // the LP slots of the p2 group the FTQ accepted and their direction;
  // the p3 group of the same index must agree and must not name SC.
  logic [NUM_PRED_SLOTS-1:0] lp2_src [0:FTQ_DEPTH-1];
  logic [NUM_PRED_SLOTS-1:0] lp2_tkn [0:FTQ_DEPTH-1];
  int                        n_lp_kept;
  int                        n_lp_bad;
  always @(posedge clk) begin : lp_keep_log
    if (rstn && dut.u_ftq.w_ok_pred_p1) lp2_src[dut.bpu_pred_idx_p1] <= '0;
    if (rstn && dut.u_ftq.w_ok_slot_p2) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        lp2_src[dut.bpu_slot_idx_p2][s] <=
          dut.bpu_slot_p2[s].slot_valid &&
          (dut.bpu_slot_p2[s].pred_src == PRED_LOOP);
        lp2_tkn[dut.bpu_slot_idx_p2][s] <= dut.bpu_slot_p2[s].taken;
      end
    end
    if (meas && dut.u_ftq.w_ok_slot_p3) begin
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (lp2_src[dut.bpu_slot_idx_p3][s]) begin
          if ((dut.bpu_slot_p3[s].taken == lp2_tkn[dut.bpu_slot_idx_p3][s])
              && (dut.bpu_slot_p3[s].pred_src != PRED_SC))
            n_lp_kept <= n_lp_kept + 1;
          else
            n_lp_bad  <= n_lp_bad + 1;
        end
      end
    end
  end

  int n_p2_blk;
  // BP-121: FTB lookups an update took the read port from (TD#162),
  // and p2 cycles in which a block the FTQ squashed still operated on
  // the RAS (FE-14).
  int n_ftb_drop;
  int n_ras_sq;
  always @(posedge clk) begin : resp_log
    if (meas) begin
      if (dut.u_bpu.r_val_p2) n_p2_blk <= n_p2_blk + 1;
      if (dut.u_bpu.u_ftb.u_ftb_cntrl.valid_p1 &&
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_active)
        n_ftb_drop <= n_ftb_drop + 1;
      if (dut.u_bpu.r_val_p2 && !dut.u_ftq.w_ok_blk_p2 &&
          dut.u_bpu.w_ras_pred_val_p2.or())   // any slot (BP-128)
        n_ras_sq <= n_ras_sq + 1;
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_tage_pred_rdy_p2[0]) begin
        if (dut.u_bpu.w_tage_pred_meta_p2[0].branch_id == dut.u_bpu.r_idx_p2)
          n_tage_ok <= n_tage_ok + 1;
        else
          n_tage_late <= n_tage_late + 1;
      end
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_ittage_pred_rdy_p2[0]) begin
        if (dut.u_bpu.w_ittage_pred_meta_p2[0].branch_id == dut.u_bpu.r_idx_p2)
          n_it_ok <= n_it_ok + 1;
        else
          n_it_late <= n_it_late + 1;
      end
      if (dut.u_bpu.r_val_p3 && dut.u_bpu.w_sc_pred_rdy_p3[0]) begin
        if (dut.u_bpu.w_sc_pred_meta_p3[0].branch_id == dut.u_bpu.r_idx_p3)
          n_sc_ok <= n_sc_ok + 1;
        else
          n_sc_late <= n_sc_late + 1;
      end
    end
  end

  always @(posedge clk) begin : use_log
    int lp;
    int lp2;
    int ras;
    int tg;
    int it;
    int sc;
    int fl;
    lp  = 0;
    lp2 = 0;
    ras = 0;
    tg  = 0;
    it  = 0;
    sc  = 0;
    fl  = 0;
    if (meas) begin
      if (dut.u_ftq.w_ok_pred_p1 && dut.u_bpu.r_ubtb_blk_p1.hit)
        n_use_ubtb <= n_use_ubtb + 1;
      if (dut.u_ftq.w_ok_slot_p2) n_use_ftb <= n_use_ftb + 1;
      if (dut.u_bpu.w_ftb_upd_val_u0) n_u_ftb <= n_u_ftb + 1;
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (dut.u_ftq.w_ok_pred_p1 && dut.bpu_pred_slot_p1[s].slot_valid) begin
          if (dut.bpu_pred_slot_p1[s].pred_src == PRED_LOOP) lp++;
          if (dut.bpu_pred_slot_p1[s].pred_src == PRED_RAS)  ras++;
        end
        if (dut.u_ftq.w_ok_slot_p2 && dut.bpu_slot_p2[s].slot_valid) begin
          if (dut.bpu_slot_p2[s].pred_src == PRED_TAGE)   tg++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_LOOP)   lp2++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_ITTAGE) it++;
          if (dut.bpu_slot_p2[s].pred_src == PRED_RAS)    ras++;
        end
        if (dut.u_ftq.w_ok_slot_p3 && dut.bpu_slot_p3[s].slot_valid &&
            (dut.bpu_slot_p3[s].br_type == COND)) begin
          if (dut.u_bpu.w_sc_hit_p3[s])                  sc++;
          if (dut.bpu_slot_p3[s].pred_src == PRED_SC)    fl++;
        end
      end
      n_use_lp     <= n_use_lp     + lp;
      n_use_lp2    <= n_use_lp2    + lp2;
      n_use_ras    <= n_use_ras    + ras;
      n_use_tage   <= n_use_tage   + tg;
      n_use_ittage <= n_use_ittage + it;
      n_use_sc     <= n_use_sc     + sc;
      n_sc_flip    <= n_sc_flip    + fl;
    end
  end

  // Per FTQ index, the last TAGE p2 view of the watched block.
  logic [14:0] tg_prm [0:FTQ_DEPTH-1];
  logic        tg_tkn [0:FTQ_DEPTH-1];
  logic [11:0] tg_alc [0:FTQ_DEPTH-1];
  logic [7:0]  tg_ghr [0:FTQ_DEPTH-1];
  logic [1:0]  tg_sc  [0:FTQ_DEPTH-1];   // {SC answered, SC direction}
  // The block start whose TAGE view the trace prints (+WATCH=<hex>).
  logic [15:0] watch16;
  initial begin
    watch16 = '1;
    void'($value$plusargs("WATCH=%h", watch16));
  end

  // The 8 newest history bits below the pointer, newest first.
  function automatic logic [7:0] ghr_window(input logic [GHR_WIDTH-1:0] g,
                                            input logic [GHIST_PTR_BITS-1:0] p);
    logic [7:0] w;
    for (int k = 0; k < 8; k++)
      w[7-k] = g[(int'(p) - 1 - k + GHR_WIDTH) % GHR_WIDTH];
    return w;
  endfunction

  function automatic string slot_str(input bp_ftq_slot_t s);
    if (!s.slot_valid) return "-";
    return $sformatf("%0d/p%0d/%s/%0h/s%0d", s.br_type, s.pos,
                     s.taken ? "T" : "N", s.target[15:0], s.pred_src);
  endfunction

  // The trace prints slots 0 and 1 (BP-128). At NUM_PRED_SLOTS 1 there
  // is no slot 1: S1 is NUM_PRED_SLOTS-1, slot 1 at two slots and an
  // index the trace does not print at one ("-" and a redirect of 0).
  localparam int S1 = NUM_PRED_SLOTS - 1;
  localparam bit HAS_S1 = (NUM_PRED_SLOTS > 1);

  always @(posedge clk) begin : trace_log
    if (trace && rstn) begin
      if (dut.ftq_pred_val_p0)
        $display("%0d P0 pc %0h idx %0d", cyc, dut.ftq_pred_pc_p0[15:0],
                 dut.ftq_pred_idx_p0);
      if (dut.bpu_pred_val_p1)
        $display("%0d P1 idx %0d ok %0d hit %0d pft %0h s0 %s s1 %s", cyc,
                 dut.bpu_pred_idx_p1, dut.u_ftq.w_ok_pred_p1,
                 dut.u_bpu.r_ubtb_blk_p1.hit, dut.bpu_pred_pft_p1[15:0],
                 slot_str(dut.bpu_pred_slot_p1[0]),
                 HAS_S1 ? slot_str(dut.bpu_pred_slot_p1[S1]) : "-");
      if (dut.u_bpu.r_val_p2)
        $display({"%0d P2 idx %0d ok %0d ftb %0d pft %0h s0 %s s1 %s",
                  " r %0d/%0h %0d/%0h ras t%0d w%0d b%0d"}, cyc,
                 dut.bpu_slot_idx_p2, dut.u_ftq.w_ok_blk_p2,
                 dut.bpu_slot_val_p2, dut.bpu_blk_pft_p2[15:0],
                 slot_str(dut.bpu_slot_p2[0]),
                 HAS_S1 ? slot_str(dut.bpu_slot_p2[S1]) : "-",
                 dut.bpu_redir_p2[0].valid,
                 dut.bpu_redir_p2[0].target_pc[15:0],
                 HAS_S1 && dut.bpu_redir_p2[S1].valid,
                 HAS_S1 ? dut.bpu_redir_p2[S1].target_pc[15:0] : 16'h0,
                 dut.bpu_blk_ras_p2.tosr, dut.bpu_blk_ras_p2.tosw,
                 dut.bpu_blk_ras_p2.bos);
      if (dut.u_bpu.r_val_p3)
        $display("%0d P3 idx %0d ok %0d s0 %s s1 %s r %0d/%0h %0d/%0h", cyc,
                 dut.bpu_slot_idx_p3, dut.u_ftq.w_ok_slot_p3,
                 slot_str(dut.bpu_slot_p3[0]),
                 HAS_S1 ? slot_str(dut.bpu_slot_p3[S1]) : "-",
                 dut.bpu_redir_p3[0].valid,
                 dut.bpu_redir_p3[0].target_pc[15:0],
                 HAS_S1 && dut.bpu_redir_p3[S1].valid,
                 HAS_S1 ? dut.bpu_redir_p3[S1].target_pc[15:0] : 16'h0);
      if (dut.u_ftq.w_redir_val)
        $display({"%0d REDIR arm %b idx %0d self %0d pc %0h rb %0d/%0d",
                  " ras %0d/%0d/%0d"}, cyc,
                 dut.u_ftq.w_arm_win, dut.u_ftq.w_redir_idx,
                 dut.u_ftq.w_redir_self, dut.ftq_pred_pc_p0[15:0],
                 dut.ftq_rollback_val, dut.ftq_rollback_idx,
                 dut.ras_restore_snapshot.tosr,
                 dut.ras_restore_snapshot.tosw,
                 dut.ras_restore_snapshot.bos);
      if (dut.ftq_ifu_req_val && dut.ftq_ifu_req_rdy)
        $display("%0d FETCH idx %0d start %0h next %0h tk %0d/%0d", cyc,
                 dut.ftq_ifu_idx, dut.ftq_ifu_start_pc[15:0],
                 dut.ftq_ifu_next_pc[15:0], dut.ftq_ifu_taken_val,
                 dut.ftq_ifu_taken_pos);
      if (dut.ftb_upd_valid_u0)
        $display({"%0d FTBUPD pc %0h hit %0d way %0d br %0d/%0d tk %0d pos %0d",
                  " jmp %0d c%0d r%0d j%0d pft %0h tgt %0h"}, cyc,
                 dut.ftb_upd_pc_u0[15:0], dut.ftb_upd_hit_u0,
                 dut.ftb_upd_way_u0, dut.ftb_upd_is_br_u0,
                 dut.ftb_upd_br_idx_u0, dut.ftb_upd_taken_u0,
                 dut.ftb_upd_pos_u0, dut.ftb_upd_is_jmp_u0,
                 dut.ftb_upd_is_call_u0,
                 dut.ftb_upd_is_ret_u0, dut.ftb_upd_is_jalr_u0,
                 dut.ftb_upd_pft_addr_u0[15:0],
                 dut.ftb_upd_jmp_target_u0[15:0]);
      if (dut.ras_commit_val)
        $display("%0d RASCOMMIT %0d ret %0h", cyc, dut.ras_commit_br_type,
                 dut.ras_commit_ret_addr[15:0]);
      for (int t = 0; t < NUM_PRED_SLOTS; t++) begin
        if (dut.u_bpu.w_ittage_upd_val_u0[t])
          $display({"%0d ITUPD s%0d hit %0d prm %0d/%0h alc %0d/%0h/%0h",
                    " mis %0d tgt %0h ptgt %0h"}, cyc, t,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_hit,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_prm_comp,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_prm_idx,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_comp,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_idx,
                   dut.ittage_upd_inp_u0[t].ittage_pred_meta.ittage_alc_tag,
                   dut.ittage_upd_inp_u0[t].indir_mispredict,
                   {dut.ittage_upd_inp_u0[t].resolved_target[14:0], 1'b0},
                   {dut.ittage_upd_inp_u0[t].ittage_pred_meta
                      .ittage_prm_tgt[14:0], 1'b0});
      end
      $display({"%0d TG p0v %0d p2v %0d idx2 %0d trdy %0d tbid %0d cr %0d",
                " scgu %0d pqnf %0d scr %0d"}, cyc,
               dut.u_bpu.w_req_val_p0, dut.u_bpu.r_val_p2, dut.u_bpu.r_idx_p2,
               dut.u_bpu.w_tage_pred_rdy_p2[0],
               dut.u_bpu.w_tage_pred_meta_p2[0].branch_id,
               dut.u_bpu.w_tage_consumer_ready, dut.u_bpu.w_sc_grant_upd,
               dut.u_bpu.tage_pq_not_full, dut.u_bpu.sc_ready);
      if (dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2[15:0] == watch16))
        $display({"%0d TGP2 idx %0d rdy %0d bid %0d prm %0d/%0h alt %0d/%0h",
                  " ctr %0d tkn %0d alc %0d/%0h use_prm %0d ghp %0d ghr %b"},
                 cyc,
                 dut.u_bpu.r_idx_p2, dut.u_bpu.w_tage_pred_rdy_p2[0],
                 dut.u_bpu.w_tage_pred_meta_p2[0].branch_id,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alt_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alt_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_ctr,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_pred_tkn,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_comp,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_idx,
                 dut.u_bpu.w_tage_pred_meta_p2[0].tage_using_primary,
                 dut.bpu_ghist_ptr,
                 ghr_window(dut.bpu_ghr_buf, dut.bpu_ghist_ptr));
      if (dut.u_bpu.r_val_p2 && (dut.u_bpu.r_pc_p2[15:0] == watch16)) begin
        tg_prm[dut.u_bpu.r_idx_p2] <=
          {dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_comp,
           12'(dut.u_bpu.w_tage_pred_meta_p2[0].tage_prm_idx)};
        tg_tkn[dut.u_bpu.r_idx_p2] <=
          dut.u_bpu.w_tage_pred_meta_p2[0].tage_pred_tkn;
        tg_alc[dut.u_bpu.r_idx_p2] <=
          12'(dut.u_bpu.w_tage_pred_meta_p2[0].tage_alc_idx);
        tg_ghr[dut.u_bpu.r_idx_p2] <=
          ghr_window(dut.bpu_ghr_buf, dut.bpu_ghist_ptr);
      end
      if (dut.u_bpu.r_val_p3)
        tg_sc[dut.u_bpu.r_idx_p3] <= {dut.u_bpu.w_sc_hit_p3[0],
                                      dut.u_bpu.w_taken_p3[0]};
      for (int t = 0; t < NUM_PRED_SLOTS; t++) begin
        if (dut.u_bpu.w_tage_upd_val_u0[t])
          $display({"%0d TGUPD s%0d bid %0d prm %0d/%0h alc %0d/%0h tkn %0d",
                    " mis %0d"}, cyc, t,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.branch_id,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_prm_comp,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_prm_idx,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_alc_comp,
                   dut.tage_upd_inp_u0[t].tage_pred_meta.tage_alc_idx,
                   dut.tage_upd_inp_u0[t].resolved_taken,
                   dut.tage_upd_inp_u0[t].cond_mispredict);
      end
      if (dut.u_bpu.r_val_p2 && dut.u_bpu.w_ittage_pred_rdy_p2[0])
        $display("%0d ITP2 idx %0d bid %0d hit %0d prm %0d/%0h alc %0d/%0h/%0h",
                 cyc, dut.u_bpu.r_idx_p2,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].branch_id,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_hit,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_prm_comp,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_prm_idx,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_comp,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_idx,
                 dut.u_bpu.w_ittage_pred_meta_p2[0].ittage_alc_tag);
    end
  end

  always @(posedge clk) begin : upd_log
    // Per-slot terms over every slot (BP-128: slots 0 and 1 written out).
    int   nub;
    int   nic;
    int   nit;
    logic r2;
    logic r3;
    nub = 0;
    r2  = 1'b0;
    r3  = 1'b0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      if (dut.u_bpu.w_ubtb_upd_u0[s].valid) nub++;
      r2 = r2 || dut.bpu_redir_p2[s].valid;
      r3 = r3 || dut.bpu_redir_p3[s].valid;
    end
    if (meas) begin
      n_u_ubtb   <= n_u_ubtb   + nub;
      n_u_lp     <= n_u_lp     + $countones(dut.u_bpu.w_lp_upd_val_p0);
      n_u_tage   <= n_u_tage   + $countones(dut.u_bpu.w_tage_upd_val_u0);
      n_u_ittage <= n_u_ittage + $countones(dut.u_bpu.w_ittage_upd_val_u0);
      n_u_sc     <= n_u_sc     + $countones(dut.u_bpu.w_sc_upd_val_u0);
      for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
        if (dut.u_bpu.w_ras_pred_val_p2[s] &&
            (dut.u_bpu.w_br_type_p2[s] == RETURN_CALL))
          n_rc_p2 <= n_rc_p2 + 1;
      end
      if (dut.u_bpu.w_ras_commit_val) n_u_ras <= n_u_ras + 1;
      if (dut.u_bpu.w_ras_commit_val &&
          (dut.ras_commit_br_type == RETURN_CALL))
        n_rc_commit <= n_rc_commit + 1;
      // A p2 or p3 redirect the FTQ accepted: the stage group is
      // live (w_ok_redir_*) and a slot of it redirects.
      if (dut.u_ftq.w_ok_redir_p2 && r2)
        n_redir_p2 <= n_redir_p2 + 1;
      if (dut.u_ftq.w_ok_redir_p3 && r3)
        n_redir_p3 <= n_redir_p3 + 1;
      // A resolution whose position names no slot of its entry
      // (ftq_resolve rsv_nomap): placed in a slot and trained since
      // BP-119. Channel 0 is the one the backend model drives.
      if (dut.u_ftq.w_rsv_nomap[0] && ftq_bkend_rsv_rdy[0])
        n_nomap <= n_nomap + 1;
      // BP-139, item C. An accepted resolution placed in a slot that
      // holds a valid branch at another position: its position names no
      // slot, and the slot ftq_resolve placed it in is valid in the
      // entry it read. n_plc_tbl counts those whose slot trained TAGE,
      // SC, LP or ITTAGE in that cycle, the training through another
      // branch's metadata that item C stops. Formed from the entry and
      // the chosen slot, not from the item C term, so the same count
      // runs on a tree without item C.
      nic = 0;
      nit = 0;
      for (int c = 0; c < NUM_RESOLVE_PORTS; c++) begin
        if (dut.u_ftq.w_rsv_nomap[c] && ftq_bkend_rsv_rdy[c] &&
            (bkend_ftq_rsv[c].br_type != NO_BRANCH) &&
            dut.u_ftq.w_rsv_entry[c].slot[dut.u_ftq.w_rsv_slot[c]]
              .slot_valid) begin
          nic++;
          if (dut.u_ftq.w_upd_tage_val[dut.u_ftq.w_rsv_slot[c]] ||
              dut.u_ftq.w_upd_sc_val[dut.u_ftq.w_rsv_slot[c]]   ||
              dut.u_ftq.w_upd_lp_val[dut.u_ftq.w_rsv_slot[c]]   ||
              dut.u_ftq.w_upd_ittage_val[dut.u_ftq.w_rsv_slot[c]])
            nit++;
        end
      end
      n_plc_occ <= n_plc_occ + nic;
      n_plc_tbl <= n_plc_tbl + nit;
      // BP-120, TD#156: an FTB jump update that hits an entry whose
      // jump field holds a jump at a different region position. Since
      // BP-120 the field is replaced; before, it kept the stored
      // position. Read from ftb_cntrl's update decode: the carried
      // way's readback and the update's region position.
      if (dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_valid_u0 &&
          dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_is_jmp_u0 &&
`ifdef BASE_RTL
          dut.u_bpu.u_ftb.u_ftb_cntrl.ftb_upd_hit_u0 &&
`else
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_hit &&
`endif
          dut.u_bpu.u_ftb.u_ftb_cntrl.upd_old.jmp.valid &&
          (dut.u_bpu.u_ftb.u_ftb_cntrl.upd_old.jmp.pos !=
           dut.u_bpu.u_ftb.u_ftb_cntrl.upd_rpos))
        n_jmp_swap <= n_jmp_swap + 1;
    end
  end

  // The backend's hooks (models/fe_tb_backend.svh). Retirement: the
  // WBR line of the cycle trace, a conditional of the watched block.
  task automatic be_retire_hook(input ifu_pd_pkt_t s, input int e);
    if (trace && (W.ex[e].btype == COND) &&
        (fstart[s.ftq_idx][15:0] == watch16))
      $display({"%0d WBR pc %0h act %0d tage %0d sc %b prm %0d/%0h",
                " alc %0h ghr %b"}, cyc,
               s.start_pc[15:0], W.ex[e].taken, tg_tkn[s.ftq_idx],
               tg_sc[s.ftq_idx],
               tg_prm[s.ftq_idx][14:12], tg_prm[s.ftq_idx][11:0],
               tg_alc[s.ftq_idx], tg_ghr[s.ftq_idx]);
  endtask

  // A trap's retirement: nothing beyond the backend's own.
  task automatic be_trap_hook(input int e);
  endtask

  // BP-124, pt_upriv: the page up_vpn's walks and the ITLB's ITLB-10b
  // drop of a held fault for it.
  logic [VA_WIDTH-13:0]    up_vpn;
  logic                    up_wval;     // a walk for up_vpn in progress
  logic [1:0]              up_wpriv;    //   its privilege
  int                      n_up_wu_flt; // walks at U answered fault
  int                      n_up_ws_hit; // walks at S answered hit
  int                      n_up_drop;   // held faults dropped (ITLB-10b)

  // =================================================================
  // BP-124, pt_upriv. The walks for up_vpn by privilege, from the walk
  // port (one walk at a time, MMU-U2, so the next answer that is not a
  // retry is this walk's), and the ITLB's drop of a held fault for it:
  // a re-request answered miss while a fault held for up_vpn at another
  // privilege or V is dropped (itlb.sv w_rq_miss, w_flt_drop).
  // =================================================================
  always @(posedge clk) begin
    if (rstn && itlb_l2t_req_val && itlb_l2t_req_rdy &&
        (itlb_l2t_vpn == up_vpn)) begin
      up_wval  <= 1'b1;
      up_wpriv <= itlb_l2t_priv;
    end
    if (rstn && up_wval && l2t_itlb_rsp_val && (l2t_itlb_status != 2'b10))
    begin
      up_wval <= 1'b0;
      if ((up_wpriv == 2'd0) && (l2t_itlb_status == 2'b01))
        n_up_wu_flt <= n_up_wu_flt + 1;
      if ((up_wpriv == 2'd1) && (l2t_itlb_status == 2'b00))
        n_up_ws_hit <= n_up_ws_hit + 1;
    end
    if (rstn && dut.u_itlb.w_rq_miss && (dut.u_itlb.w_flt_drop != '0) &&
        (dut.u_itlb.r_rq_vpn == up_vpn))
      n_up_drop <= n_up_drop + 1;
  end

  // =================================================================
  // BP-123, Problem 4. Every cycle of every program:
  //   - an uncached L1I request is presented only when every retired
  //     instruction's entry has been committed, and only for the line
  //     of the next instruction to retire, or the line after it
  //     (IFU-22: nothing older is uncommitted; nothing off the path)
  //   - no fill is written into the L1I array for a line on an NC or
  //     IO page (L1I-24, MMU-14)
  //   - an ibuf transfer holding an instruction from an NC or IO page
  //     holds that one instruction alone (IFU-23), and every retired
  //     instruction's entry has committed
  // The sources are the testbench's own: its retirement and commit
  // state, its page attributes and its expected stream.
  // =================================================================
  int n_uc_req;
  int n_uc_bad;
  int n_uc_fill_bad;
  int n_uc_dlv;
  int n_uc_dlv_bad;

  function automatic logic [PA_WIDTH-1:L1I_OFFSET_BITS] va_line(
      input logic [VA_WIDTH-1:0] va);
    logic [VA_WIDTH-13:0] v;
    logic [PA_WIDTH-1:0]  pa;
    v = va[VA_WIDTH-1:12];
    if ((W.sv39 || W.h2) && !W.vmap.exists(v)) return '1;
    pa = W.va2pa(va);
    return pa[PA_WIDTH-1:L1I_OFFSET_BITS];
  endfunction

  initial begin : uc_checks
    logic [PA_WIDTH-1:L1I_OFFSET_BITS] rl;
    logic [VA_WIDTH-1:0]               pc;
    int                                n;
    logic                              uc;
    forever begin
    @(posedge clk);
    if (rstn && run_be) begin
      if (dut.ifu_l1i_req_val && dut.ifu_l1i_req_uncached) begin
        n_uc_req++;
        rl = dut.ifu_l1i_req_paddr[PA_WIDTH-1:L1I_OFFSET_BITS];
        pc = W.ex[(ep < W.ne) ? ep : 0].pc;
        if (!cm_all || (ep >= W.ne) ||
            !((rl == va_line(pc)) ||
              (rl == va_line({pc[VA_WIDTH-1:6], 6'd0} + VA_WIDTH'(64))))) begin
          n_uc_bad++;
          if (n_uc_bad <= 4)
            $display("%s", $sformatf(
              {"ERROR: [%s] uncached request %09h: committed %0d, ",
               "next pc %011h"}, tname, dut.ifu_l1i_req_paddr, cm_all, pc));
        end
      end
      for (int b = 0; b < 2; b++) begin
        if (dut.u_l1i.u_mshr.b_fil_valid[b] &&
            W.uc_ppn.exists(
              dut.u_l1i.u_mshr.b_fil_line[b][PA_WIDTH-1:12])) begin
          n_uc_fill_bad++;
          $display("ERROR: [%s] an uncached line %09h was written into the L1I",
                   tname, dut.u_l1i.u_mshr.b_fil_line[b]);
        end
      end
      if (dut.ifu_ibuf_val && dut.ibuf_ifu_rdy) begin
        n  = 0;
        uc = 1'b0;
        for (int i = 0; i < FTQ_PD_WIDTH; i++) begin
          if (dut.ifu_ibuf_en[i]) begin
            n++;
            if (W.uc_vpn.exists(dut.ifu_ibuf_slot[i].start_pc[VA_WIDTH-1:12]))
              uc = 1'b1;
          end
        end
        if (uc) begin
          n_uc_dlv++;
          if ((n != 1) || !cm_all) begin
            n_uc_dlv_bad++;
            $display("%s", $sformatf(
              {"ERROR: [%s] uncached delivery of %0d instructions, ",
               "committed %0d"}, tname, n, cm_all));
          end
        end
      end
    end
    end
  end

  `include "fe_tb_backend.svh"

  `include "fe_tb_csr.svh"

  // =================================================================
  // Scaffolding.
  // =================================================================
  // Every model to its start (models_reset), and this file's own
  // counters.
  task automatic reset_all(input logic use_sv39);
    models_reset(use_sv39);
    n_use_ubtb   = 0;
    n_use_lp     = 0;
    n_use_lp2    = 0;
    n_lp_kept    = 0;
    n_lp_bad     = 0;
    n_use_ftb    = 0;
    n_use_tage   = 0;
    n_use_sc     = 0;
    n_sc_flip    = 0;
    n_use_ittage = 0;
    n_use_ras    = 0;
    n_u_ftb      = 0;
    n_tage_ok    = 0;
    n_tage_late  = 0;
    n_it_ok      = 0;
    n_it_late    = 0;
    n_sc_ok      = 0;
    n_sc_late    = 0;
    n_p2_blk     = 0;
    n_hist_mis   = 0;
    n_ftb_drop   = 0;
    n_ras_sq     = 0;
    n_p3_no_p2   = 0;
    n_p3_rep     = 0;
    n_undo_rdec  = 0;
    n_undo_ok    = 0;
    n_undo_bad   = 0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) ud_pend[s] = 1'b0;
    n_t0u_pred   = 0;
    n_t0u_upd    = 0;
    n_t0u_ok     = 0;
    n_t0u_bad    = 0;
    for (int r = 1; r <= 8; r++) n_t0u_row[r] = 0;
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      t0u_pend[s] = 1'b0;
      uaon_max[s] = 0;
    end
    n_rest_rep   = 0;
    n_own_ok     = 0;
    n_own_bad    = 0;
    n_jmp_swap   = 0;
    n_u_ubtb     = 0;
    n_u_lp       = 0;
    n_u_tage     = 0;
    n_u_ittage   = 0;
    n_u_sc       = 0;
    n_u_ras      = 0;
    n_rc_p2      = 0;
    n_rc_commit  = 0;
    n_redir_p2   = 0;
    n_redir_p3   = 0;
    n_nomap      = 0;
    n_plc_occ    = 0;
    n_plc_tbl    = 0;
    up_vpn        = '1;
    up_wval       = 1'b0;
    up_wpriv      = '0;
    n_up_wu_flt   = 0;
    n_up_ws_hit   = 0;
    n_up_drop     = 0;
    n_uc_req      = 0;
    n_uc_bad      = 0;
    n_uc_fill_bad = 0;
    n_uc_dlv      = 0;
    n_uc_dlv_bad  = 0;
  endtask

  // Run until the whole stream has retired, then stop taking decode's
  // output so the front end backs up and nothing more retires, and
  // check that the FTQ commits through the watermark.
  int cyc_run;

  task automatic run_and_check(input int max_cyc);
    int c;
    c = 0;
    while ((ep < W.ne) && (c < max_cyc) && (n_err < 20)) begin
      @(posedge clk);
      #1;
      c++;
    end
    cyc_run = c;
    run_be = 1'b0;
    repeat (200) @(posedge clk);
    #1;
    chk($sformatf("the whole stream retired: %0d of %0d in %0d cycles",
                  ep, W.ne, c), ep == W.ne);
    chk($sformatf("no stream, decode or index error (%0d)", n_err),
        n_err == 0);
    chk("every retired instruction is the executed stream, in order",
        n_retired == W.ne);
    chk($sformatf("the FTQ committed through the watermark: ptr %0d wm %0d",
                  dut.u_ftq.w_commit_ptr, wm),
        wm_val && (dut.u_ftq.w_commit_ptr == wm + FTQ_PTR_BITS'(1)));
    chk("every resolution was accepted", rq_hd == rq_tl);
    // BP-123, Problem 4, every program.
    chk($sformatf({"no uncached request before older commits or off ",
                   "the path (%0d of %0d)"}, n_uc_bad, n_uc_req),
        n_uc_bad == 0);
    chk($sformatf("no uncached line written into the L1I (%0d)", n_uc_fill_bad),
        n_uc_fill_bad == 0);
    chk($sformatf({"uncached instructions delivered one at a time ",
                   "(%0d bad of %0d)"}, n_uc_dlv_bad, n_uc_dlv),
        n_uc_dlv_bad == 0);
    chk($sformatf("the walker's memory port kept WM-1 and WM-3 (%0d)",
                  n_pw_bad), n_pw_bad == 0);
    $display("%s", $sformatf(
      {"   BP123 %s: uncached requests %0d, uncached deliveries %0d; ",
       "maintenance %0d (drained %0d); walks %0d, walker accesses %0d, ",
       "CAS %0d, changed %0d, errors %0d; eager resolutions %0d, ",
       "CSR writes %0d, faults checked %0d"}, tname, n_uc_req, n_uc_dlv,
      n_maint, n_maint_drain, n_walks, n_pw_acc, n_pw_cas, n_pw_chg,
      n_pw_err, n_eager_res, n_csrw, n_fault_ok));
    $display("%s", $sformatf(
             {"   %s: %0d retired in %0d cycles, %0d mispredicts, %0d ",
              "traps, %0d predecode redirects, %0d resolutions, %0d L1I ",
              "fills, %0d walks, commit ptr %0d"}, tname, n_retired, c,
             n_mispred, n_trap, n_pd_redir, rq_tl, n_fills, n_walks,
             dut.u_ftq.w_commit_ptr));
    $display("%s", $sformatf(
             {"   %s: redirects p2 %0d p3 %0d, unmapped resolutions %0d; ",
              "updates received uBTB %0d ",
              "LP %0d TAGE %0d SC %0d ITTAGE %0d, RAS commits %0d; ",
              "RETURN_CALL at p2 %0d, committed %0d"}, tname, n_redir_p2,
             n_redir_p3, n_nomap, n_u_ubtb, n_u_lp, n_u_tage, n_u_sc,
             n_u_ittage, n_u_ras, n_rc_p2, n_rc_commit));
    $display("%s", $sformatf(
             {"   %s: RAS mispredicts %0d; FTB jump field trained by a ",
              "jump at another position %0d"}, tname, n_mis_ras,
             n_jmp_swap));
    // BP-139: item C occasions, and those that trained a table predictor.
    $display("%s", $sformatf(
             {"   ITEMC %s placed in an occupied slot %0d, of them ",
              "trained TAGE/SC/LP/ITTAGE %0d"}, tname, n_plc_occ,
             n_plc_tbl));
    // BP-121.
    chk($sformatf("every RAS commit is the retired stream's (%0d ok, %0d bad)",
                  n_ras_ok, n_ras_bad), n_ras_bad == 0);
    chk($sformatf("every retired RAS operation committed (%0d left)",
                  ras_exp.size()), ras_exp.size() == 0);
    chk($sformatf("no late TAGE / ITTAGE / SC response (%0d %0d %0d)",
                  n_tage_late, n_it_late, n_sc_late),
        (n_tage_late == 0) && (n_it_late == 0) && (n_sc_late == 0));
    chk($sformatf("no FTB lookup dropped by an FTB update (%0d)",
                  n_ftb_drop), n_ftb_drop == 0);
    chk($sformatf("no RAS operation by a squashed block (%0d)", n_ras_sq),
        n_ras_sq == 0);
    chk($sformatf("no p3 slot write without the p2 slot group (%0d)",
                  n_p3_no_p2), n_p3_no_p2 == 0);
    chk($sformatf({"a p2 redirect keeps its block's RAS operation ",
                   "(%0d ok, %0d bad)"}, n_own_ok, n_own_bad),
        n_own_bad == 0);
    chk($sformatf({"an LP direction at p2 is kept at p3 (%0d ok, %0d bad)"},
                  n_lp_kept, n_lp_bad), n_lp_bad == 0);
    chk($sformatf({"after a conditional's mispredict the newest history ",
                   "bit is its resolved direction (%0d ok, %0d bad)"},
                  n_hist_ok, n_hist_bad), n_hist_bad == 0);
    report();
  endtask

  // The BP-121 report: the program line the Results Capture table is
  // built from, the after-warm-up breakdown, the PCs that mispredict
  // more than once after warm-up, and per predictor the updates
  // received and the predictions used.
  task automatic report();
    $display("%s", $sformatf(
      {"   RESULT %s cycles %0d mispredicts %0d warm %0d [cond %0d ret %0d ",
       "rc %0d ind %0d icall %0d] pd %0d p2 %0d p3 %0d warm_e %0d of %0d"},
      tname, cyc_run, n_mispred, n_mis_warm, n_mis_type[int'(COND)],
      n_mis_type[int'(RETURN)], n_mis_type[int'(RETURN_CALL)],
      n_mis_type[int'(INDIRECT_NONRET)], n_mis_type[int'(INDIRECT_CALL)],
      n_pd_redir, n_redir_p2, n_redir_p3, warm_e, W.ne));
    // BP-125: the M3 conditional writebacks (n_m3_cond).
    $display("   M3COND %s %0d of %0d predecode redirects", tname, n_m3_cond,
             n_pd_redir);
    foreach (mis_pc[p]) begin
      if (mis_pc[p] > 1)
        $display("   REPEAT %s pc %011h type %0d mispredicted %0d times",
                 tname, p, mis_typ[p], mis_pc[p]);
    end
    $display("%s", $sformatf(
      {"   PRED %s upd/used: uBTB %0d/%0d LP %0d/%0d/%0d FTB %0d/%0d ",
       "TAGE %0d/%0d SC %0d/%0d(flip %0d) ITTAGE %0d/%0d RAS %0d/%0d"},
      tname, n_u_ubtb, n_use_ubtb, n_u_lp, n_use_lp, n_use_lp2, n_u_ftb,
      n_use_ftb,
      n_u_tage, n_use_tage, n_u_sc, n_use_sc, n_sc_flip, n_u_ittage,
      n_use_ittage, n_u_ras, n_use_ras));
    $display("%s", $sformatf(
      {"   CHK %s RAS commits ok %0d; history after a mispredict ok %0d; ",
       "own p2 redirect RAS ok %0d; p3 writes without p2 %0d; ",
       "squashed RAS ops %0d; dropped FTB lookups %0d; p3 RAS repairs %0d, ",
       "backend restores naming a repaired entry %0d; LP p2 directions ",
       "kept at p3 %0d, not kept %0d"}, tname, n_ras_ok,
      n_hist_ok, n_own_ok, n_p3_no_p2, n_ras_sq, n_ftb_drop, n_p3_rep,
      n_rest_rep, n_lp_kept, n_lp_bad));
    $display("%s", $sformatf(
      {"   RESP %s on time/late: TAGE %0d/%0d ITTAGE %0d/%0d SC %0d/%0d ",
       "p2 blocks %0d, history bundle changed at p2 without a ",
       "redirect %0d"}, tname, n_tage_ok, n_tage_late, n_it_ok, n_it_late,
      n_sc_ok, n_sc_late, n_p2_blk, n_hist_mis));
  endtask

  // =================================================================
  // Program 1, bare (V=0, satp.MODE Bare, M-mode): physical fetch.
  // =================================================================
  task automatic p_bare();
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    tname = "bare";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
    // Straight-line mixed 16- and 32-bit code, then a 32-bit
    // instruction straddling the line boundary at 0x40.
    W.mixed(20);
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h3E)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(5);
    // Never taken, then always taken.
    W.cond(1'b0, W.wp + VA_WIDTH'('h40));
    W.mixed(3);
    W.cond(1'b1, RESET_VECTOR + VA_WIDTH'('h100));
    W.mixed(4);
    // JAL forward.
    W.jal(5'd0, RESET_VECTOR + VA_WIDTH'('h180));
    W.mixed(3);
    // Call and return, three times to the same function.
    fn = RESET_VECTOR + VA_WIDTH'('h400);
    for (int k = 0; k < 3; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(4);
      W.cond(1'b1, W.wp + VA_WIDTH'(8));        // a taken branch in it
      W.i32(ADDI_T0);
      W.ret(link);
      W.mixed(2);
    end
    // A 32-bit instruction straddling the page boundary at 0x1000.
    W.jal(5'd0, RESET_VECTOR + VA_WIDTH'('hFF0));
    while (W.wp != RESET_VECTOR + VA_WIDTH'('hFFE)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(6);
    // An ecall: a trap redirect to the handler.
    W.ecall(RESET_VECTOR + VA_WIDTH'('h2000));
    W.mixed(4);
    // An access fault: a fetch just below main memory (MMU-15a)
    // faults with cause 1 and traps to the second handler. Within JAL
    // range of the handler.
    W.jal_fault(VA_WIDTH'('h0_7FFF_F000), IFU_FAULT_ACCESS,
              RESET_VECTOR + VA_WIDTH'('h3000));
    W.mixed(5);
    fn = RESET_VECTOR + VA_WIDTH'('h3400);
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, fn);
    W.mixed(2);
    W.ret(link);
    W.mixed(2);
    // BP-121: straight-line code; nothing is after warm-up.
    warm_e = W.ne + 1;
    W.halt();
    release_reset();
    run_and_check(20000);
    chk($sformatf("a predecode redirect occurred (%0d)", n_pd_redir),
        n_pd_redir > 0);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
    chk($sformatf("two backend trap redirects occurred (%0d)", n_trap),
        n_trap == 2);
    chk("the access fault reached decode with its cause and VA",
        n_fault_ok == 1);
  endtask

  // =================================================================
  // Program 2, Sv39 (V=0, satp.MODE Sv39, S-mode).
  // =================================================================
  task automatic p_sv39();
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    tname = "sv39";
    $display("-- %s --", tname);
    reset_all(1'b1);
    // Three code pages, not physically contiguous, and a handler page.
    // b + 0x4000 is not mapped. All within JAL range of each other.
    b = VA_WIDTH'('h0_8001_0000);
    W.map4k(b,                       PA_WIDTH'('h0_8100_0000));
    W.map4k(b + VA_WIDTH'('h1000),   PA_WIDTH'('h0_8120_5000));
    W.map4k(b + VA_WIDTH'('h2000),   PA_WIDTH'('h0_8100_7000));
    W.map4k(VA_WIDTH'('h0_8002_0000), PA_WIDTH'('h0_8130_0000));
    // The reset vector is fetched physically before any translation,
    // so it jumps to the program; under Sv39 that fetch is already
    // translated, so the reset vector page is mapped to itself.
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, b);
    W.mixed(10);
    W.cond(1'b1, b + VA_WIDTH'('h200));
    W.mixed(3);
    // A 32-bit instruction straddling into the next, discontiguous
    // page.
    W.jal(5'd0, b + VA_WIDTH'('hFF0));
    while (W.wp != b + VA_WIDTH'('hFFE)) W.i16();
    W.i32(ADDI_T0);
    W.mixed(4);
    fn = b + VA_WIDTH'('h2100);
    for (int k = 0; k < 2; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(3);
      W.ret(link);
      W.mixed(2);
    end
    // A page fault: a fetch from an unmapped VA, cause 12.
    W.jal_fault(b + VA_WIDTH'('h4000), IFU_FAULT_PAGE,
              VA_WIDTH'('h0_8002_0000));
    W.mixed(6);
    // BP-121: straight-line code; nothing is after warm-up.
    warm_e = W.ne + 1;
    W.halt();
    release_reset();
    run_and_check(20000);
    chk($sformatf("the L2 TLB walked (%0d)", n_walks), n_walks > 0);
    chk("the page fault reached decode with its cause and VA",
        n_fault_ok == 1);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
  endtask

  // =================================================================
  // Program 3, loops (bare). An outer loop of 8 iterations around an
  // inner counted loop of 6, so the inner loop branch runs the same
  // trip count again and again (the LP's case). The outer body holds
  // a conditional that is always taken (TAGE, SC), an indirect jump
  // and an indirect call to a function that returns (ITTAGE, RAS).
  // =================================================================
  // BP-122, TD#169: the loop predictor's end state in lp and loops.
  // It supplies directions the entry keeps (p2), and the inner loop's
  // branch at br_pc mispredicts at most once after warm-up.
  localparam int LOOPS_OUTER = 14;
  localparam int LOOPS_WARM  = 8;
  localparam int LP_OUTER    = 16;
  localparam int LP_WARM     = 8;

  task automatic lp_end_chk(input logic [VA_WIDTH-1:0] br_pc);
    int n;
    n = mis_pc.exists(br_pc) ? mis_pc[br_pc] : 0;
    chk($sformatf("%s: the LP supplied p2 directions (%0d)", tname,
                  n_use_lp2), n_use_lp2 > 0);
    chk($sformatf("%s: the loop exit at %011h mispredicted %0d times %s",
                  tname, br_pc, n, "after warm-up (at most 1)"), n <= 1);
  endtask

  // BP-137: the stream and the checks after it are tasks of their own,
  // so init_walk runs this same stream without fast init.
  task automatic loops_write();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] link;
    int                  eo;
    int                  ei;
    W.wp = RESET_VECTOR;
    W.mixed(4);
    fn   = RESET_VECTOR + VA_WIDTH'('h800);
    otop = W.wp;
    eo   = W.ne;
    // Outer body, first iteration.
    W.mixed(2);
    itop = W.wp;
    ei   = W.ne;
    W.mixed(3);
    W.loop_br(itop);
    W.rep_iter(ei, 6);
    W.cond(1'b1, W.wp + VA_WIDTH'(12));            // always taken, skips 8
    W.mixed(2);
    // jalr x0, 0(x7): an indirect jump to a fixed target 0x40 ahead.
    W.jalr_to(5'd0, 5'd7, W.wp + VA_WIDTH'('h40));
    W.mixed(2);
    // jalr x1, 0(x28): an indirect call to fn, which returns.
    link = W.wp + VA_WIDTH'(4);
    W.jalr_to(5'd1, 5'd28, fn);
    W.mixed(3);
    W.ret(link);
    W.mixed(1);
    W.loop_br(otop);
    // BP-122 (ruled by Jeff): 14 outer iterations, warm-up after 8. The
    // loop predictor is trusted after five exits of the inner loop at
    // the earliest (one with no count, one to learn it, three
    // confirmations); BP-121 ran 8 and warmed up after 2.
    W.rep_iter(eo, LOOPS_OUTER);
    warm_e = eo + LOOPS_WARM * ((W.ne - eo) / LOOPS_OUTER);
    W.mixed(3);
    W.halt();
  endtask

  task automatic loops_checks();
    chk($sformatf("the uBTB received updates (%0d)", n_u_ubtb), n_u_ubtb > 0);
    chk($sformatf("the LP received updates (%0d)", n_u_lp), n_u_lp > 0);
    chk($sformatf("TAGE received updates (%0d)", n_u_tage), n_u_tage > 0);
    chk($sformatf("SC received updates (%0d)", n_u_sc), n_u_sc > 0);
    chk($sformatf("ITTAGE received updates (%0d)", n_u_ittage),
        n_u_ittage > 0);
    chk($sformatf("the RAS committed (%0d)", n_u_ras), n_u_ras > 0);
    // BP-128 (provisional, decision 5): two-slot only. The inner loop
    // branch (+0x18) and the always-taken conditional after it (+0x1c)
    // are two conditionals of one block. At NUM_PRED_SLOTS 1 the second
    // has no slot: it mispredicts every outer iteration, and ftq_resolve
    // places its resolution in the last slot (BP-119 rule), the loop
    // branch's, so the LP never becomes trusted for +0x18. The lp
    // program, whose loop branch is alone in its block, keeps both
    // checks at one slot.
    if (NUM_PRED_SLOTS > 1) begin
      lp_end_chk(VA_WIDTH'(RESET_VECTOR) + VA_WIDTH'('h18));
    end else begin
      $display("SKIP %s: the LP supplied p2 directions: %s", tname,
               "needs NUM_PRED_SLOTS > 1");
      $display("SKIP %s: the loop exit mispredicted at most once: %s",
               tname, "needs NUM_PRED_SLOTS > 1");
    end
  endtask

  task automatic p_loops();
    tname = "loops";
    $display("-- %s --", tname);
    reset_all(1'b0);
    loops_write();
    release_reset();
    run_and_check(60000);
    loops_checks();
  endtask

  // =================================================================
  // BP-137. init_walk: the loops stream with the real SRAM init walks.
  // =================================================================
  // Run WITHOUT the fast-init plusargs (its own target,
  // sim_fe_top_init_walk), so TAGE, ITTAGE and SC walk their tables
  // after reset and their readies rise at the end of the walk. The FTQ
  // must present no p0 request until all three are high (the RAM Init
  // Interface sections of tage_, ittage_ and sc_interfaces.md, ruled
  // session-080), and no predictor may answer a prediction or take an
  // update before its own ready. The stream must then retire exactly,
  // with the loops program's checks.
  //
  // The monitor records, in cycles after reset (cyc), when each ready
  // was first seen high, whether it was seen low first, the first p0
  // request, the first accepted p1 prediction, and the first response
  // and first update of each queued predictor; and counts the cycles
  // with a p0 request while any ready was low. The count is the
  // testbench's own check of the hold, independent of fe_top_assert I1.
  int   ini_tage_rdy;
  int   ini_it_rdy;
  int   ini_sc_rdy;
  logic ini_tage_lo;
  logic ini_it_lo;
  logic ini_sc_lo;
  int   ini_p0;
  int   ini_p1;
  int   ini_tage_rsp;
  int   ini_it_rsp;
  int   ini_sc_rsp;
  int   ini_tage_upd;
  int   ini_it_upd;
  int   ini_sc_upd;
  int   ini_p0_early;

  task automatic init_mon_reset();
    ini_tage_rdy = -1;
    ini_it_rdy   = -1;
    ini_sc_rdy   = -1;
    ini_tage_lo  = 1'b0;
    ini_it_lo    = 1'b0;
    ini_sc_lo    = 1'b0;
    ini_p0       = -1;
    ini_p1       = -1;
    ini_tage_rsp = -1;
    ini_it_rsp   = -1;
    ini_sc_rsp   = -1;
    ini_tage_upd = -1;
    ini_it_upd   = -1;
    ini_sc_upd   = -1;
    ini_p0_early = 0;
  endtask

  initial init_mon_reset();

  always @(posedge clk) begin : init_mon
    if (rstn) begin
      if (!dut.bpu_tage_rdy)   ini_tage_lo <= 1'b1;
      if (!dut.bpu_ittage_rdy) ini_it_lo   <= 1'b1;
      if (!dut.bpu_sc_ready)   ini_sc_lo   <= 1'b1;
      if (dut.bpu_tage_rdy   && (ini_tage_rdy < 0)) ini_tage_rdy <= cyc;
      if (dut.bpu_ittage_rdy && (ini_it_rdy   < 0)) ini_it_rdy   <= cyc;
      if (dut.bpu_sc_ready   && (ini_sc_rdy   < 0)) ini_sc_rdy   <= cyc;
      if (dut.ftq_pred_val_p0 && (ini_p0 < 0))      ini_p0       <= cyc;
      if (dut.ftq_pred_val_p0 &&
          !(dut.bpu_tage_rdy && dut.bpu_ittage_rdy && dut.bpu_sc_ready))
        ini_p0_early <= ini_p0_early + 1;
      if (dut.u_ftq.w_ok_pred_p1 && (ini_p1 < 0))   ini_p1       <= cyc;
      if ((dut.u_bpu.w_tage_pred_rdy_p2 != '0) && (ini_tage_rsp < 0))
        ini_tage_rsp <= cyc;
      if ((dut.u_bpu.w_ittage_pred_rdy_p2 != '0) && (ini_it_rsp < 0))
        ini_it_rsp <= cyc;
      if ((dut.u_bpu.w_sc_pred_rdy_p3 != '0) && (ini_sc_rsp < 0))
        ini_sc_rsp <= cyc;
      if ((dut.u_bpu.w_tage_upd_val_u0 != '0) && (ini_tage_upd < 0))
        ini_tage_upd <= cyc;
      if ((dut.u_bpu.w_ittage_upd_val_u0 != '0) && (ini_it_upd < 0))
        ini_it_upd <= cyc;
      if ((dut.u_bpu.w_sc_upd_val_u0 != '0) && (ini_sc_upd < 0))
        ini_sc_upd <= cyc;
    end
  end

  // An event at cycle ev is no earlier than a ready that rose at rdy:
  // it did not happen (-1), or the ready had risen and ev is not before
  // it. A ready that never rose (-1) fails any event that did happen.
  function automatic logic ini_after(input int ev, input int rdy);
    return (ev < 0) || ((rdy >= 0) && (ev >= rdy));
  endfunction

  task automatic p_init_walk();
    int last;
    tname = "init_walk";
    $display("-- %s --", tname);
    reset_all(1'b0);
    init_mon_reset();
    loops_write();
    release_reset();
    run_and_check(60000);
    loops_checks();
    last = ini_tage_rdy;
    if (ini_it_rdy > last) last = ini_it_rdy;
    if (ini_sc_rdy > last) last = ini_sc_rdy;
    $display("%s", $sformatf(
      {"   INIT %s ready rose TAGE %0d ITTAGE %0d SC %0d ",
       "(seen low %0d%0d%0d); ",
       "first p0 %0d, first accepted p1 %0d; first response TAGE %0d ",
       "ITTAGE %0d SC %0d; first update TAGE %0d ITTAGE %0d SC %0d; ",
       "early p0 cycles %0d"}, tname, ini_tage_rdy, ini_it_rdy, ini_sc_rdy,
      ini_tage_lo, ini_it_lo, ini_sc_lo, ini_p0, ini_p1, ini_tage_rsp,
      ini_it_rsp, ini_sc_rsp, ini_tage_upd, ini_it_upd, ini_sc_upd,
      ini_p0_early));
    // The walks ran: each ready was low after reset and then rose. Run
    // with the fast-init plusargs, these fail.
    chk("init_walk: each init ready was seen low after reset",
        ini_tage_lo && ini_it_lo && ini_sc_lo);
    chk("init_walk: each init ready rose",
        (ini_tage_rdy >= 0) && (ini_it_rdy >= 0) && (ini_sc_rdy >= 0));
    chk($sformatf({"init_walk: the first p0 request (%0d) follows the ",
                   "last ready (%0d)"}, ini_p0, last),
        (ini_p0 >= 0) && ini_after(ini_p0, ini_tage_rdy) &&
        ini_after(ini_p0, ini_it_rdy) && ini_after(ini_p0, ini_sc_rdy));
    chk($sformatf("init_walk: no p0 request while a ready was low (%0d)",
                  ini_p0_early), ini_p0_early == 0);
    chk("init_walk: no p1 prediction accepted before the last ready",
        (ini_p1 >= 0) && ini_after(ini_p1, ini_tage_rdy) &&
        ini_after(ini_p1, ini_it_rdy) && ini_after(ini_p1, ini_sc_rdy));
    chk("init_walk: no TAGE, ITTAGE or SC response before its ready",
        ini_after(ini_tage_rsp, ini_tage_rdy) &&
        ini_after(ini_it_rsp, ini_it_rdy) &&
        ini_after(ini_sc_rsp, ini_sc_rdy));
    chk("init_walk: no TAGE, ITTAGE or SC update before its ready",
        ini_after(ini_tage_upd, ini_tage_rdy) &&
        ini_after(ini_it_upd, ini_it_rdy) &&
        ini_after(ini_sc_upd, ini_sc_rdy));
    // The predictors answered and trained after the walks, so the two
    // checks above are not met by nothing happening.
    chk("init_walk: TAGE, ITTAGE and SC each responded and were updated",
        (ini_tage_rsp >= 0) && (ini_it_rsp >= 0) && (ini_sc_rsp >= 0) &&
        (ini_tage_upd >= 0) && (ini_it_upd >= 0) && (ini_sc_upd >= 0));
  endtask

  // =================================================================
  // Program 4, coro (bare). Two coroutines, A (the loop) and B,
  // switching by RETURN_CALL. Each iteration:
  //   L:   jal  x5, B            call, x5 = L+4 (push L+4)
  //   B:   ...                   B's prologue
  //   B1:  jalr x1, 0(x5)        RETURN_CALL: to L+4, x1 = B1+4
  //   L+4: ...
  //   A1:  jalr x5, 0(x1)        RETURN_CALL: to B1+4, x5 = A1+4
  //   B1+4: ...
  //   B2:  jalr x0, 0(x5)        RETURN: to A1+4
  //   A1+4: ... bne x6, x0, L
  // The stack is level across the iteration: a push, two pop-then-
  // pushes, a pop. Each RETURN_CALL's target is the other coroutine's
  // resume address, the top of the stack.
  // =================================================================
  task automatic p_coro();
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] b;
    logic [VA_WIDTH-1:0] b1;
    logic [VA_WIDTH-1:0] a1;
    int                  e0;
    tname = "coro";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    b  = RESET_VECTOR + VA_WIDTH'('h600);
    l  = W.wp;
    e0 = W.ne;
    W.jal(5'd5, b);                          // L
    W.mixed(3);                              // B prologue
    b1 = W.wp;
    W.jalr_to(5'd1, 5'd5, l + VA_WIDTH'(4)); // B1: RETURN_CALL
    W.mixed(2);                              // A at L+4
    a1 = W.wp;
    W.jalr_to(5'd5, 5'd1, b1 + VA_WIDTH'(4)); // A1: RETURN_CALL
    W.mixed(2);                              // B at B1+4
    W.jalr_to(5'd0, 5'd5, a1 + VA_WIDTH'(4)); // B2: RETURN
    W.mixed(1);                              // A at A1+4
    W.loop_br(l);
    W.rep_iter(e0, 10);
    // BP-121: after two iterations.
    warm_e = e0 + 2 * ((W.ne - e0) / 10);
    W.mixed(3);
    W.halt();
    release_reset();
    run_and_check(40000);
    chk($sformatf("the p2 classification formed RETURN_CALL (%0d)",
                  n_rc_p2), n_rc_p2 > 0);
    chk($sformatf("the RAS committed RETURN_CALLs (%0d, 2 per iteration)",
                  n_rc_commit), n_rc_commit == 20);
  endtask

  // =================================================================
  // Program 5, calls (bare), BP-120, TD#159. Six iterations of:
  //   main: jal x1, f            push Lm
  //   f:    jal x1, g            push Lf1
  //   g:    ret                  pop  -> Lf1
  //   f:    jal x1, h            push Lf2
  //   h:    ret                  pop  -> Lf2
  //   f:    ret                  pop  -> Lm
  //   main: bne x6, x0, top
  // f's return follows a pop then a push. Before BP-120 the pop of
  // Lf2 moved TOSR to TOSR-1, the slot Lf1 was popped from, so f's
  // return was predicted to Lf1 (ras_decisions.md 3.2).
  //
  // THE LAYOUT KEEPS ONE JUMP PER FTB ENTRY. An FTB entry is indexed by
  // the region of the block START and holds one jump (5.5, TD#156), and
  // a block that starts at a return address runs on into the next
  // region. So each call is the last instruction of its 32-byte region
  // and its return address is the next region's start: main's call at
  // +0x1C, f's at f+0x1C and f+0x3C, f's return at f+0x42, g's and h's
  // returns at g+6 and h+6. Each block start then finds only its own
  // jump, and the block end the FTB records is the call's return
  // address, which is what the RAS pushes (IC-FTB-03).
  // =================================================================
  task automatic p_calls();
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] lm;
    logic [VA_WIDTH-1:0] lf1;
    logic [VA_WIDTH-1:0] lf2;
    int                  e0;
    tname = "calls";
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp  = RESET_VECTOR;
    f   = RESET_VECTOR + VA_WIDTH'('h800);
    g   = RESET_VECTOR + VA_WIDTH'('hA00);
    h   = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    e0  = W.ne;
    while (W.wp != RESET_VECTOR + VA_WIDTH'('h1C)) W.i16();
    lm  = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);                          // main calls f
    W.mixed(3);
    while (W.wp != f + VA_WIDTH'('h1C)) W.i16();
    lf1 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, g);                          // f calls g
    W.mixed(2);
    W.ret(lf1);                              // g returns
    W.mixed(1);
    while (W.wp != f + VA_WIDTH'('h3C)) W.i16();
    lf2 = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, h);                          // f calls h
    W.mixed(2);
    W.ret(lf2);                              // h returns
    W.mixed(1);
    watch_pc = W.wp;                         // f's return
    W.ret(lm);                               // f returns to main
    W.mixed(1);
    W.loop_br(top);
    W.rep_iter(e0, 6);
    // BP-121: after two iterations.
    warm_e = e0 + 2 * ((W.ne - e0) / 6);
    W.mixed(3);
    W.halt();
    release_reset();
    run_and_check(40000);
    // Reported, not checked: f's return still mispredicts in every
    // iteration, before BP-120 and after, for reasons outside TD#159
    // (the BP-120 Results Capture: the FTB lookup of the block after a
    // redirect is dropped when an FTB update borrows the read port, so
    // main's call is not pushed at p2). The RAS mispredict count is the
    // before/after measure of the link.
    $display("   %s: f's return mispredicted %0d times in 6 iterations",
             tname, n_mis_watch);
  endtask

  // =================================================================
  // BP-121 programs. Each loop is emitted once per iteration (see the
  // file header); warm_e is set at the start of the first iteration
  // counted as after warm-up.
  // =================================================================



  task automatic begin_prog(input string nm);
    tname = nm;
    $display("-- %s --", tname);
    reset_all(1'b0);
    W.wp = RESET_VECTOR;
  endtask

  task automatic end_prog(input int max_cyc);
    W.halt();
    if ($test$plusargs("DUMPEX")) begin
      for (int e = 0; e < W.ne; e++)
        $display("EX %0d pc %0h instr %08h rvc %0d bt %0d tk %0d tgt %0h", e,
                 W.ex[e].pc[15:0], W.ex[e].instr, W.ex[e].rvc, W.ex[e].btype,
                 W.ex[e].taken, W.ex[e].target[15:0]);
    end
    release_reset();
    run_and_check(max_cyc);
  endtask

  // -----------------------------------------------------------------
  // lp: a counted inner loop of 10 inside an outer loop of 12. The
  // inner loop branch has the same trip count every time (the loop
  // predictor's case).
  // -----------------------------------------------------------------
  task automatic p_lp();
    logic [VA_WIDTH-1:0] otop;
    logic [VA_WIDTH-1:0] itop;
    begin_prog("lp");
    W.mixed(3);
    otop = W.wp;
    // BP-122 (ruled by Jeff): 16 outer iterations, warm-up at 8 (12 and
    // 4 before); see LOOPS_OUTER.
    for (int o = 0; o < LP_OUTER; o++) begin
      if (o == LP_WARM) warm_e = W.ne;
      W.wp = otop;
      W.mixed(2);
      itop = W.wp;
      for (int i = 0; i < 10; i++) begin
        W.wp = itop;
        W.mixed(3);
        W.bcc(i != 9, itop);
      end
      W.mixed(2);
      W.bcc(o != LP_OUTER - 1, otop);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("lp: the LP trained (%0d updates; %0d directions used)",
                  n_u_lp, n_use_lp), n_u_lp > 0);
    lp_end_chk(VA_WIDTH'(RESET_VECTOR) + VA_WIDTH'('h16));
  endtask

  // -----------------------------------------------------------------
  // hist: two branches whose outcomes depend on history (TAGE). A
  // alternates not taken / taken; B is not taken twice then taken.
  // Neither is predictable from its own bias. 96 iterations, the second
  // 48 after warm-up: TAGE allocates one tagged entry per history
  // context on a mispredict, and the six contexts of the combined
  // pattern take most of the first 48 to settle (measured: with a
  // 16-iteration warm-up the period-3 branch still mispredicted 9 of
  // 32; with 48, 3 mispredicts in 48 iterations, none repeating).
  // -----------------------------------------------------------------
  task automatic p_hist();
    logic [VA_WIDTH-1:0] top;
    begin_prog("hist");
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 96; it++) begin
      if (it == 48) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      W.cskip((it % 2) == 1, 2);              // A
      W.mixed(1);
      W.cskip((it % 3) == 2, 2);              // B
      W.mixed(1);
      W.bcc(it != 95, top);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("hist: TAGE supplied a direction (%0d)", n_use_tage),
        n_use_tage > 0);
  endtask

  // -----------------------------------------------------------------
  // twocond: two conditionals in one block, both slots. Each block
  // sits alone in its 32-byte region, so no other start shares its
  // FTB entry (the shared case is multistart's and region's). Block X:
  // c1 never taken, c2 always taken. Block Y: c1 alternates, c2 never
  // taken. X jumps to Y, Y to the loop branch.
  // -----------------------------------------------------------------
  task automatic p_twocond();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] y;
    logic [VA_WIDTH-1:0] back;
    begin_prog("twocond");
    x = RESET_VECTOR + VA_WIDTH'('h400);
    y = RESET_VECTOR + VA_WIDTH'('h440);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      W.jal(5'd0, x);
      back = top + VA_WIDTH'(6);
      W.i16();
      W.cskip(1'b0, 1);                     // X c1
      W.cskip(1'b1, 1);                     // X c2
      W.i16();
      W.jal(5'd0, y);
      W.i16();
      W.cskip((it % 2) == 1, 1);            // Y c1
      W.cskip(1'b0, 1);                     // Y c2
      W.i16();
      W.jal(5'd0, back);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // ftbonly: eight blocks 0x800 apart, chained by taken conditionals.
  // They share one uBTB set (pc[10:5]) of four ways and occupy eight
  // FTB sets (pc[13:5]), so the FTB holds every branch and the uBTB
  // cannot.
  // -----------------------------------------------------------------
  task automatic p_ftbonly();
    logic [VA_WIDTH-1:0] b [0:7];
    logic [VA_WIDTH-1:0] ex_pc;
    begin_prog("ftbonly");
    for (int k = 0; k < 8; k++)
      b[k] = RESET_VECTOR + VA_WIDTH'('h1000 + k * 'h800);
    W.mixed(3);
    W.jal(5'd0, b[0]);
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      for (int k = 0; k < 7; k++) begin
        W.wp = b[k];
        W.mixed(2);
        W.bcc(1'b1, b[k+1]);
      end
      W.wp = b[7];
      W.mixed(1);
      ex_pc = W.wp + VA_WIDTH'(8);
      W.bcc(it == 15, ex_pc);                 // exit on the last pass
      if (it != 15) begin
        W.jal(5'd0, b[0]);
      end else begin
        W.d_jal_fill();
      end
    end
    W.mixed(3);
    end_prog(80000);
  endtask


  // -----------------------------------------------------------------
  // nest: calls nested five deep, main -> f1 -> f2 -> f3 -> f4 -> f5.
  // -----------------------------------------------------------------

  task automatic p_nest();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    begin_prog("nest");
    for (int k = 1; k <= 5; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h100);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 12; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 5, l);
      W.mixed(1);
      W.bcc(it != 11, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // recur: one function calling itself six deep from one call site,
  // so the RAS sees the same return address pushed again and again
  // (the recursion counter, ras_decisions.md 5). Layout of f:
  //   f+0   mixed(2)        6 bytes
  //   f+6   beq -> f+16     taken at the bottom of the recursion
  //   f+10  jal x1, f       link f+14
  //   f+14  c.addi
  //   f+16  ret
  // -----------------------------------------------------------------

  task automatic p_recur();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] l;
    begin_prog("recur");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    // The not-taken path of the bottom beq (f+10..f+16) is written by
    // the first call; the taken bottom is written here too, dry.
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 10; it++) begin
      if (it == 3) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.emit_rec(f, 6, l);
      W.mixed(1);
      W.bcc(it != 9, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // rec_undo (BP-134): an undo of a pop that decremented a recursion
  // count (TD#78, BP-133 Problem 2). f calls itself six deep from one
  // call site (as recur), so the return address f+14 is pushed once and
  // its recursion count raised five times; each return but the
  // outermost pops by decrementing it, TOSR held. Every return of f is
  // in the block [bne][ret] at f+14 (two slots of one FTB entry), and
  // the bne's outcome is pseudo-random, so TAGE stays weak and SC can
  // reverse it at p3: when p2 predicted not taken (the ret reachable,
  // popped) and p3 predicts taken, the ret is not reachable at p3 and
  // the p3 pass undoes the pop. When that pop decremented the count,
  // the undo must put it back, or the stack is one level short and a
  // later return of the recursion pops to the caller's address.
  // -----------------------------------------------------------------
  localparam int RU_ITERS = 48;
  localparam int RU_WARM  = 8;
  localparam int RU_DEPTH = 6;

  task automatic p_rec_undo();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] l;
    begin_prog("rec_undo");
    // Seed chosen from a sweep of eight, each of which reached the case
    // at two slots (2 to 10 times in 48 iterations); this one 10.
    // BP-139: re-chosen. With item C the first execution of f's bne
    // (placed in the slot predecode gave the jal) no longer trains TAGE,
    // and 16'h3039 reached the case 0 times. Of 16 seeds swept on the
    // BP-139 tree 12 reach it (1 to 5 times); this one 5.
    W.lfsr = 16'hacef;
    f = RESET_VECTOR + VA_WIDTH'('h800);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < RU_ITERS; it++) begin
      if (it == RU_WARM) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      // The return blocks' bne, innermost return first: taken with
      // probability 1/4 (two LFSR bits both set). At 1/2 the backend
      // mispredicts it so often that wrong-path pops wear the recursion
      // count down and the undos land on link pops instead.
      W.rc_tk.delete();
      for (int k = 0; k <= RU_DEPTH; k++)
        W.rc_tk.push_back(W.lfsr_bit() & W.lfsr_bit());
      W.jal(5'd1, f);
      W.emit_rcx(f, RU_DEPTH, l);
      W.mixed(1);
      W.bcc(it != RU_ITERS - 1, top);
    end
    W.mixed(3);
    end_prog(120000);
    $display("   UNDO %s undo-pops over a recursion pop %0d, compared %0d,",
             tname, n_undo_rdec, n_undo_ok + n_undo_bad);
    $display("   UNDO %s count put back %0d, not put back %0d", tname,
             n_undo_ok, n_undo_bad);
`ifndef BASE_RTL
    // The case is the program's purpose at two slots. At one slot an FTB
    // entry has one slot, so no return shares a block with a branch
    // before it, p3 reachability is constant, and the case does not
    // arise; the count is reported, not checked.
    if (NUM_PRED_SLOTS > 1)
      chk($sformatf("rec_undo: an undo-pop over a recursion pop ran (%0d)",
                    n_undo_rdec), n_undo_ok + n_undo_bad > 0);
    chk($sformatf({"rec_undo: each undo put the recursion count back ",
                   "(%0d ok, %0d not)"}, n_undo_ok, n_undo_bad),
        n_undo_bad == 0);
`endif
  endtask

  // -----------------------------------------------------------------
  // t0_uaon (BP-135): T0 as the TAGE provider through use_alt_on_na,
  // then updated (CTR rows 19.1-19.8, BP-133). One block per
  // iteration: mixed(2), a conditional B taken with probability 1/8
  // (three LFSR bits all set) that skips one instruction, mixed(1) and
  // the loop branch. B is slot 0 of its block.
  // How the case arises. A taken B mispredicts and allocates a tagged
  // entry above its provider, at 100 (weakly taken). The next visit in
  // the same history context is usually not taken: that entry is the
  // primary, weak and wrong, with a tagged alternate that is right, so
  // the slot's use_alt_on_na counter rises (tage_cntrl uaon_upd_ff).
  // Once its MSB is set, a weak primary in T1, whose alternate is T0,
  // hands the prediction to T0 (pred_logic), and the update of that
  // prediction is the 19.x case.
  // Seed and length from a sweep of eight seeds at 128 and 256
  // iterations at both slot counts: at 256 every seed but two reached
  // the case at two slots and six of eight at one; this seed gave the
  // most at one slot.
  // -----------------------------------------------------------------
  localparam int TU_ITERS = 256;
  localparam int TU_WARM  = 8;

  task automatic p_t0_uaon();
    logic [VA_WIDTH-1:0] top;
    logic                tk;
    begin_prog("t0_uaon");
    W.lfsr = 16'hACE1;
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < TU_ITERS; it++) begin
      if (it == TU_WARM) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      tk = W.lfsr_bit() & W.lfsr_bit() & W.lfsr_bit();
      W.cskip(tk, 1);                         // B
      W.mixed(1);
      W.bcc(it != TU_ITERS - 1, top);
    end
    W.mixed(3);
    end_prog(200000);
    $display("%s", $sformatf({"   T0UAON %s predictions %0d, updates %0d, ",
             "T0 write ok %0d not ok %0d; uaon max s0 %0d s%0d %0d"}, tname,
             n_t0u_pred, n_t0u_upd, n_t0u_ok, n_t0u_bad, uaon_max[0],
             NUM_PRED_SLOTS - 1, uaon_max[NUM_PRED_SLOTS-1]));
    $display("%s", $sformatf({"   T0UAON %s rows 19.1 %0d 19.2 %0d 19.3 %0d ",
             "19.4 %0d 19.5 %0d 19.6 %0d 19.7 %0d 19.8 %0d"}, tname,
             n_t0u_row[1], n_t0u_row[2], n_t0u_row[3], n_t0u_row[4],
             n_t0u_row[5], n_t0u_row[6], n_t0u_row[7], n_t0u_row[8]));
`ifndef BASE_RTL
    chk($sformatf("t0_uaon: T0 was updated as the use_alt_on_na provider (%0d)",
                  n_t0u_upd), n_t0u_upd > 0);
    chk($sformatf("t0_uaon: each such update wrote T0 (%0d ok, %0d not)",
                  n_t0u_ok, n_t0u_bad),
        (n_t0u_bad == 0) && (n_t0u_ok == n_t0u_upd));
`endif
  endtask

  // -----------------------------------------------------------------
  // deep: a chain of 18 distinct functions, f0 -> f1 -> ... -> f17,
  // so 18 distinct return addresses are live: beyond the 15 usable
  // speculative entries (the wrap, ras_decisions.md 3.2).
  // -----------------------------------------------------------------
  task automatic p_deep();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] l;
    begin_prog("deep");
    for (int k = 1; k <= 18; k++)
      W.fnv[k] = RESET_VECTOR + VA_WIDTH'('h400 + k * 'h40);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 8; it++) begin
      if (it == 3) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, W.fnv[1]);
      W.emit_nest(1, 18, l);
      W.mixed(1);
      W.bcc(it != 7, top);
    end
    W.mixed(3);
    end_prog(120000);
  endtask

  // -----------------------------------------------------------------
  // indir: an indirect jump and an indirect call whose targets
  // alternate, each preceded by a conditional that alternates with
  // them, so the target is a function of global history (ITTAGE).
  // -----------------------------------------------------------------
  task automatic p_indir();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] ta;
    logic [VA_WIDTH-1:0] tb;
    logic [VA_WIDTH-1:0] jn;
    logic [VA_WIDTH-1:0] fa;
    logic [VA_WIDTH-1:0] fb;
    logic [VA_WIDTH-1:0] l;
    logic                odd;
    begin_prog("indir");
    ta = RESET_VECTOR + VA_WIDTH'('h400);
    tb = RESET_VECTOR + VA_WIDTH'('h480);
    jn = RESET_VECTOR + VA_WIDTH'('h500);
    fa = RESET_VECTOR + VA_WIDTH'('h600);
    fb = RESET_VECTOR + VA_WIDTH'('h680);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 40; it++) begin
      if (it == 16) warm_e = W.ne;
      odd = (it % 2) == 1;
      W.wp = top;
      W.mixed(1);
      W.cskip(odd, 1);
      W.jalr_to(5'd0, 5'd7, odd ? ta : tb);   // indirect jump
      if (odd) begin
        W.mixed(2);
        W.jal(5'd0, jn);
      end else begin
        W.mixed(1);
        W.jal(5'd0, jn);
      end
      W.mixed(1);
      W.cskip(!odd, 1);
      l = W.wp + VA_WIDTH'(4);
      W.jalr_to(5'd1, 5'd28, odd ? fa : fb);  // indirect call
      if (odd) W.mixed(2);
      else     W.mixed(1);
      W.ret(l);
      W.mixed(1);
      // The loop back edge, a JAL to the top: the loop body spans
      // several distant blocks.
      W.exit_or_jal(it == 39, top);
    end
    W.mixed(3);
    end_prog(120000);
    chk($sformatf("indir: ITTAGE supplied a target (%0d)", n_use_ittage),
        n_use_ittage > 0);
  endtask

  // -----------------------------------------------------------------
  // region: two calls and a return in one 32-byte region (TD#161):
  //   f+0x0  jal x1, g     link f+0x4
  //   f+0x4  c.addi
  //   f+0x6  jal x1, h     link f+0xA
  //   f+0xA  c.addi
  //   f+0xC  ret
  // The three blocks of f (starts f, f+0x4, f+0xA) share one FTB entry.
  // -----------------------------------------------------------------
  task automatic p_region();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    logic [VA_WIDTH-1:0] h;
    logic [VA_WIDTH-1:0] l;
    begin_prog("region");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hA00);
    h = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(2);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      W.jal(5'd1, g);
      W.mixed(1);
      W.ret(f + VA_WIDTH'('h4));
      W.i16();
      W.jal(5'd1, h);
      W.mixed(1);
      W.ret(f + VA_WIDTH'('hA));
      W.i16();
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 15, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // multistart: one region entered at two starts. Region R:
  //   R+0x00  c.addi x2
  //   R+0x04  c1, never taken          (seen from start R only)
  //   R+0x08  c.addi x2
  //   R+0x0C  c2, taken to R+0x18      (seen from both starts)
  //   R+0x18  c.addi
  //   R+0x1A  jal x0 back
  // Even iterations enter at R, odd at R+0x08.
  // -----------------------------------------------------------------
  task automatic p_multistart();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] r;
    logic [VA_WIDTH-1:0] cont;
    logic [VA_WIDTH-1:0] j1;
    logic [VA_WIDTH-1:0] j2;
    begin_prog("multistart");
    r = RESET_VECTOR + VA_WIDTH'('hC00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      // Taken on odd iterations, to the jump to R+0x08.
      j1 = W.wp + VA_WIDTH'(4);
      j2 = j1 + VA_WIDTH'(4);
      W.bcc((it % 2) == 1, j2);
      if ((it % 2) == 0) begin
        W.jal(5'd0, r);
        W.i16();
        W.i16();
        W.bcc(1'b0, r + VA_WIDTH'('h8));       // c1
      end else begin
        W.jal(5'd0, r + VA_WIDTH'('h8));
      end
      W.i16();
      W.i16();
      W.bcc(1'b1, r + VA_WIDTH'('h18));       // c2
      W.i16();
      cont = j2 + VA_WIDTH'(4);
      W.jal(5'd0, cont);
      W.mixed(1);
      W.bcc(it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask



  // -----------------------------------------------------------------
  // cross: a block crossing a 32-byte boundary, a 32-bit instruction
  // straddling it, a conditional past it, and a call as the last
  // instruction of the next region. Region X:
  //   X+0x14  entered here (region offset 10)
  //   X+0x1E  a 32-bit instruction straddling X+0x20
  //   X+0x24  conditional, taken to X+0x30 (stored in X's entry at
  //           region position 18, beyond the region)
  //   X+0x3C  jal x1, fn: the last instruction of region X+0x20
  // -----------------------------------------------------------------
  task automatic p_cross();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] x;
    logic [VA_WIDTH-1:0] fn;
    begin_prog("cross");
    x  = RESET_VECTOR + VA_WIDTH'('h900);
    fn = RESET_VECTOR + VA_WIDTH'('hB00);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 16; it++) begin
      if (it == 4) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      W.jal(5'd0, x + VA_WIDTH'('h14));
      W.i16();
      W.i16();
      W.i32(ADDI_T0);
      W.i16();
      W.i32(ADDI_T0);                          // X+0x1E, straddles
      W.i16();
      W.bcc(1'b1, x + VA_WIDTH'('h30));        // X+0x24
      W.fill_dry_at(x + VA_WIDTH'('h28), 8);
      W.pad_to(x + VA_WIDTH'('h3C));
      W.jal(5'd1, fn);                         // X+0x3C
      W.mixed(2);
      W.ret(x + VA_WIDTH'('h40));
      W.i16();
      W.jal(5'd0, top + VA_WIDTH'(6));
      // Back in the loop, after the JAL at top+2.
      W.mixed(1);
      W.bcc(it != 15, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // rvc: compressed control transfers among compressed and 32-bit
  // code: c.bnez (alternating), c.jalr x1 (a call, link pc+2), c.jr x1
  // (its return), c.j, and c.beqz as the loop branch.
  // -----------------------------------------------------------------
  task automatic p_rvc();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    logic [VA_WIDTH-1:0] b;
    begin_prog("rvc");
    fn = RESET_VECTOR + VA_WIDTH'('h100);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 24; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.i16();
      b = W.wp;
      W.cbz(1'b1, (it % 2) == 1, b + VA_WIDTH'(4));   // skips one c.addi
      if ((it % 2) == 0) W.i16();
      else               W.fill_dry_at(b + VA_WIDTH'(2), 2);
      W.i32(ADDI_T0);
      l = W.wp + VA_WIDTH'(2);
      W.cjalr(5'd1, fn);
      W.i16();
      W.i32(ADDI_T0);
      W.cjr(5'd1, l);
      W.i16();
      b = W.wp;
      W.cj(b + VA_WIDTH'(8));
      W.fill_dry_at(b + VA_WIDTH'(2), 6);
      W.i16();
      W.cbz(1'b0, it != 23, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // misp_call: a conditional the predictors cannot learn (pseudo-
  // random), then a call and its return (TD#162). After each backend
  // mispredict of the conditional the call's block is the first block
  // fetched.
  // -----------------------------------------------------------------
  task automatic p_misp_call();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] fn;
    logic [VA_WIDTH-1:0] l;
    begin_prog("misp_call");
    W.lfsr = 16'hACE1;
    fn   = RESET_VECTOR + VA_WIDTH'('h400);
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 32; it++) begin
      if (it == 8) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      W.cskip(W.lfsr_bit(), 1);
      l = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, fn);
      W.mixed(2);
      W.ret(l);
      W.mixed(1);
      W.bcc(it != 31, top);
    end
    W.mixed(3);
    end_prog(80000);
  endtask

  // -----------------------------------------------------------------
  // jals: a chain of twelve JALs to distinct blocks, run three times.
  // On the first pass every JAL is new to the predictors and predecode
  // redirects (M1).
  // -----------------------------------------------------------------
  task automatic p_jals();
    logic [VA_WIDTH-1:0] top;
    logic [VA_WIDTH-1:0] t;
    begin_prog("jals");
    W.mixed(3);
    top = W.wp;
    for (int it = 0; it < 3; it++) begin
      if (it == 1) warm_e = W.ne;
      W.wp = top;
      W.mixed(1);
      for (int k = 0; k < 12; k++) begin
        t = RESET_VECTOR + VA_WIDTH'('h200 + k * 'h60);
        W.jal(5'd0, t);
        W.mixed(2);
      end
      W.jal(5'd0, top + VA_WIDTH'('h100));
      W.wp = top + VA_WIDTH'('h100);
      W.mixed(1);
      W.bcc(it != 2, top);
    end
    W.mixed(3);
    end_prog(80000);
    chk($sformatf("jals: predecode redirected (%0d)", n_pd_redir),
        n_pd_redir > 0);
  endtask


  // =================================================================
  // BP-123 programs: maintenance (Problem 4).
  // =================================================================
  // A function at f, its old body six c.addi and a return. It is called
  // twice, so the L1I and the IFU's line buffer hold it. Then one store
  // rewrites it (three addi t1 and the return), the maintenance
  // operation retires (FENCE.I, or cbo.inval of its line), and the
  // function is called again: the stream expects the NEW body. A
  // stale fetch delivers the old one and fails the stream check.
  task automatic smc_fn(input logic [VA_WIDTH-1:0] f, input int calls);
    logic [VA_WIDTH-1:0] link;
    for (int k = 0; k < calls; k++) begin
      link = W.wp + VA_WIDTH'(4);
      W.jal(5'd1, f);
      for (int i = 0; i < 6; i++) W.i16();
      W.ret(link);
    end
  endtask

  task automatic smc_store(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] w;
    logic                d;
    W.store();
    w     = W.wp;
    d     = W.dry;
    W.dry = 1'b1;
    W.wp  = f;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(f);
    W.dry = d;
    W.wp  = w;
    W.store_end();
  endtask

  task automatic smc_call_new(input logic [VA_WIDTH-1:0] f);
    logic [VA_WIDTH-1:0] link;
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, f);
    W.nowrite = 1'b1;
    for (int i = 0; i < 3; i++) W.i32(ADDI_T1);
    W.ret(link);
    W.nowrite = 1'b0;
  endtask

  // op 1 FENCE.I, 2 cbo.inval of the function's line. Phase 1 plain;
  // phase 2 with a mispredicted branch just before the operation and
  // cold code after it, so the IFU has fetches in flight when the L1I
  // takes the invalidate.
  task automatic p_smc(input int op);
    logic [VA_WIDTH-1:0] f;
    logic [VA_WIDTH-1:0] g;
    begin_prog(op == 1 ? "fencei" : "cboinval");
    f = RESET_VECTOR + VA_WIDTH'('h800);
    g = RESET_VECTOR + VA_WIDTH'('hC40);
    W.mixed(3);
    smc_fn(f, 2);
    W.mixed(2);
    smc_store(f);
    W.mixed(2);
    if (op == 1) W.fence_i();
    else         W.cbo_inval(5'd10, PA_WIDTH'(f));
    W.mixed(2);
    smc_call_new(f);
    W.mixed(2);
    // Phase 2.
    smc_fn(g, 2);
    smc_store(g);
    W.cskip(1'b1, 1);                       // taken, cold: mispredicted
    if (op == 1) W.fence_i();
    else         W.cbo_inval(5'd10, PA_WIDTH'(g) + PA_WIDTH'('h24));
    W.mixed(60);                            // cold lines after it
    smc_call_new(g);
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(20000);
    chk($sformatf("two maintenance operations retired (%0d)", n_maint),
        n_maint == 2);
    chk($sformatf("two stores applied their patches (%0d)", n_patch),
        n_patch == 2 * 8);
    chk($sformatf("an invalidate drained fills in flight (%0d)",
                  n_maint_drain), n_maint_drain > 0);
    chk($sformatf("a backend mispredict occurred (%0d)", n_mispred),
        n_mispred > 0);
  endtask

  // =================================================================
  // BP-123 programs: uncached fetch under Sv39 (Problem 4).
  // =================================================================
  // A cacheable code page c, and a page u mapped with PBMT NC (1) or IO
  // (2). Branches into u, within it (taken and not, a jump, a counted
  // loop) and out of it; a call into u and a return out. Every
  // instruction from u must be fetched uncached, one at a time, after
  // everything older has committed (the per-cycle checks), and never
  // allocated in the L1I.
  task automatic p_uc(input logic [1:0] pbmt);
    logic [VA_WIDTH-1:0] c;
    logic [VA_WIDTH-1:0] u;
    logic [VA_WIDTH-1:0] link;
    logic [VA_WIDTH-1:0] top;
    int                  e0;
    int                  nu;
    tname = (pbmt == 2'd1) ? "uc_nc" : "uc_io";
    $display("-- %s --", tname);
    reset_all(1'b1);
    eager = 1'b1;
    c = VA_WIDTH'('h0_8001_0000);
    u = VA_WIDTH'('h0_8001_1000);
    W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
    W.map4k(c, PA_WIDTH'('h0_8100_0000));
    W.map4k_pbmt(u, PA_WIDTH'('h0_8120_3000), pbmt);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, c);
    W.mixed(4);
    W.jal(5'd0, u + VA_WIDTH'('h10));       // into u
    W.mixed(3);
    W.cskip(1'b1, 2);                       // within: taken
    W.mixed(2);
    W.cskip(1'b0, 1);                       // within: not taken
    W.jal(5'd0, u + VA_WIDTH'('h200));      // within: a jump
    top = W.wp;
    e0  = W.ne;
    W.mixed(2);
    W.loop_br(top);
    W.rep_iter(e0, 3);                      // within: a loop
    W.mixed(2);
    W.jal(5'd0, c + VA_WIDTH'('h200));      // out of u
    W.mixed(3);
    link = W.wp + VA_WIDTH'(4);
    W.jal(5'd1, u + VA_WIDTH'('h400));      // a call into u
    W.mixed(2);
    W.ret(link);                            // a return out of it
    W.mixed(2);
    nu = 0;
    for (int e = 0; e < W.ne; e++)
      if (W.uc_vpn.exists(W.ex[e].pc[VA_WIDTH-1:12])) nu++;
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("uncached requests were made (%0d)", n_uc_req),
        n_uc_req > 0);
    chk($sformatf("every instruction from the page came alone (%0d of %0d)",
                  n_uc_dlv, nu), n_uc_dlv == nu);
  endtask


  // =================================================================
  // BP-123 programs: the page table walker in RTL (Problem 4).
  // =================================================================
  // Address map of the walker programs. Code c and handlers h, mapped
  // ordinarily; fault and test targets each in its own 2 MiB region,
  // T(k), reached by an indirect jump. Handlers h + 0x40 * k.
  localparam logic [VA_WIDTH-1:0] PC_C = VA_WIDTH'('h0_8001_0000);
  localparam logic [VA_WIDTH-1:0] PC_H = VA_WIDTH'('h0_8002_0000);
  localparam logic [PA_WIDTH-1:0] PA_C = PA_WIDTH'('h0_8100_0000);
  localparam logic [PA_WIDTH-1:0] PA_H = PA_WIDTH'('h0_8130_0000);
  localparam logic [GPA_WIDTH-1:0] GP_C = GPA_WIDTH'('h0_1001_0000);
  localparam logic [GPA_WIDTH-1:0] GP_H = GPA_WIDTH'('h0_1002_0000);

  // A Svnapot 64 KiB PTE PPN for a page in the region: PPN[3:0] = 1000.
  function automatic logic [43:0] napot(input logic [43:0] page);
    return {page[43:4], 4'b1000};
  endfunction

  function automatic logic [VA_WIDTH-1:0] tgt(input int k);
    return VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(k) * VA_WIDTH'('h20_0000) +
           VA_WIDTH'('h10);
  endfunction
  function automatic logic [VA_WIDTH-1:0] hnd(input int k);
    return PC_H + VA_WIDTH'(k * 'h40);
  endfunction

  task automatic map_ch();
    if (W.h2) begin
      W.h_map4k(PC_C, GP_C, PA_C);
      W.h_map4k(PC_H, GP_H, PA_H);
    end else begin
      W.map4k(RESET_VECTOR, PA_WIDTH'(RESET_VECTOR));
      W.map4k(PC_C, PA_C);
      W.map4k(PC_H, PA_H);
    end
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(2);
  endtask

  // A two-stage mapping with chosen leaves: VA page -> GPA page by a
  // VS-stage leaf, GPA page -> SPA page by a G-stage leaf.
  task automatic h_map(input logic [VA_WIDTH-1:0] va,
                       input logic [GPA_WIDTH-1:0] gpa,
                       input logic [PA_WIDTH-1:0] spa,
                       input logic [63:0] vs_leaf, input logic [63:0] g_leaf);
    W.wr64(W.g_slot(gpa[GPA_WIDTH-1:12], 0), g_leaf);
    W.gmap[gpa[GPA_WIDTH-1:12]] = spa[PA_WIDTH-1:12];
    W.wr64(W.vs_slot(va, 0), vs_leaf);
    W.vmap[va[VA_WIDTH-1:12]] = spa[PA_WIDTH-1:12];
  endtask

  // The GPA of the VS-stage level-0 table that maps va, and the SPA of
  // the G-stage leaf that maps that table page.
  function automatic logic [GPA_WIDTH-1:0] vs_l0_gpa(
      input logic [VA_WIDTH-1:0] va);
    logic [63:0] p;
    p = W.rd64(W.vs_slot(va, 1));
    return GPA_WIDTH'(p[53:10]) << 12;
  endfunction

  // A short body at a target, then an indirect jump to a handler.
  task automatic run_at(input logic [VA_WIDTH-1:0] at,
                        input logic [VA_WIDTH-1:0] back);
    W.jalr_to(5'd0, 5'd7, at);
    W.mixed(4);
    W.jalr_to(5'd0, 5'd7, back);
    W.mixed(2);
  endtask

  // ---- single stage: every fault cause and every cause-1 source -------
  task automatic p_pt_faults_s();
    logic [PA_WIDTH-1:0] a;
    tname = "pt_faults_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    csr_menv_adue(1'b1);
    pmp_all(2);
    map_ch();
    // 0 cause 12: nothing mapped.
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.mixed(2);
    // 1 cause 1: PMP denies the read of the level-0 table.
    a = W.s_slot(tgt(1), 0);
    W.wr64(a, W.mk_pte(44'h8_1400, PTE_LEAF, 2'b00, 1'b0));
    pmp_page(0, a, 3'b000);
    W.jr_fault(tgt(1), IFU_FAULT_ACCESS, hnd(1));
    W.mixed(2);
    // 2 cause 1: PMP denies the Svadu write (the table page is R only).
    a = W.s_slot(tgt(2), 0);
    W.wr64(a, W.mk_pte(44'h8_1410, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    pmp_page(1, a, 3'b001);
    W.jr_fault(tgt(2), IFU_FAULT_ACCESS, hnd(2));
    W.mixed(2);
    // 3 cause 1: a level-0 table outside cacheable coherent memory.
    W.wr64(W.s_slot(tgt(3), 1), W.mk_pte(44'h4_0000, PTE_PTR, 2'b00, 1'b0));
    W.wr64(PA_WIDTH'('h0_4000_0000) + PA_WIDTH'(8 * tgt(3)[20:12]),
           W.mk_pte(44'h8_1420, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_ACCESS, hnd(3));
    W.mixed(2);
    // 4 cause 1: a leaf PPN above bit 23.
    W.wr64(W.s_slot(tgt(4), 0),
           W.mk_pte(44'h100_0000 | 44'h8_1430, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_ACCESS, hnd(4));
    W.mixed(2);
    // 5 cause 1: a non-leaf PPN above bit 23.
    W.wr64(W.s_slot(tgt(5), 1),
           W.mk_pte(44'h100_0000 | 44'h8_F100, PTE_PTR, 2'b00, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_ACCESS, hnd(5));
    W.mixed(2);
    // 6 cause 1: the memory port answers the leaf read with an error.
    a = W.s_slot(tgt(6), 0);
    W.wr64(a, W.mk_pte(44'h8_1440, PTE_LEAF, 2'b00, 1'b0));
    err_pa  = a;
    err_arm = 1'b1;
    W.jr_fault(tgt(6), IFU_FAULT_ACCESS, hnd(6));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("all seven faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 7);
    chk($sformatf("the memory error was returned (%0d)", n_pw_err),
        n_pw_err == 1);
  endtask

  // ---- two stage: cause 20 of each kind, the GPA width, 12 and 1 -------
  task automatic p_pt_faults_h();
    logic [GPA_WIDTH-1:0] g;
    logic [GPA_WIDTH-1:0] tg;
    logic [PA_WIDTH-1:0]  a;
    tname = "pt_faults_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_menv_adue(1'b1);
    csr_henv_adue(1'b1);
    pmp_all(2);
    map_ch();
    // 0 kind 00: the final GPA is not mapped by the G-stage.
    g = GPA_WIDTH'('h0_2000_0000);
    W.wr64(W.vs_slot(tgt(0), 0), W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.jr_gfault(tgt(0), FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(0));
    W.mixed(2);
    // 1 kind 01: a VS-stage table page is not mapped by the G-stage.
    tg = GPA_WIDTH'('h0_2100_0000);
    W.wr64(W.vs_slot(tgt(1), 1), W.mk_pte(44'(tg >> 12), PTE_PTR, 2'b00, 1'b0));
    W.jr_gfault(tgt(1),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(1)[20:12])),
                2'b01, hnd(1));
    W.mixed(2);
    // 2 kind 10: the VS leaf needs A; the G-stage leaf of its table page
    // grants no write.
    g = GPA_WIDTH'('h0_2200_0000);
    h_map(tgt(2), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1400, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(2));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'hDB, 2'b00, 1'b0));
    W.jr_gfault(tgt(2),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(2)[20:12])),
                2'b10, hnd(2));
    W.mixed(2);
    // 3 a VS leaf whose GPA has a bit above 40: the whole GPA, kind 00,
    //   the offset filled by the IFU (MMU-23, IFU-2a; BP-124: this was
    //   MMU-30's GPA 0). PPN bit 43 set, so GPA bit 55.
    W.wr64(W.vs_slot(tgt(3), 0),
           W.mk_pte(44'h800_0000_0123, PTE_LEAF, 2'b00, 1'b0));
    W.jr_gfault(tgt(3), {44'h800_0000_0123, tgt(3)[11:0]}, 2'b00, hnd(3));
    W.mixed(2);
    // 4 a VS non-leaf whose GPA has a bit above 40: the whole GPA of the
    //   VS PTE the next level reads, kind 01 (BP-124: was GPA 0).
    W.wr64(W.vs_slot(tgt(4), 1),
           W.mk_pte(44'h2000_0041, PTE_PTR, 2'b00, 1'b0));
    W.jr_gfault(tgt(4), {44'h2000_0041, 12'h000} +
                FAULT_GPA_WIDTH'(8 * tgt(4)[20:12]), 2'b01, hnd(4));
    W.mixed(2);
    // 5 cause 12: a VS leaf with W and not R.
    W.wr64(W.vs_slot(tgt(5), 0),
           W.mk_pte(44'h1234, 8'hC5, 2'b00, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(5));
    W.mixed(2);
    // 6 cause 1: a G-stage leaf PPN above bit 23.
    g = GPA_WIDTH'('h0_2400_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h100_8140, F_URWXAD, 2'b00, 1'b0));
    W.jr_fault(tgt(6), IFU_FAULT_ACCESS, hnd(6));
    W.mixed(2);
    // 7 cause 1: a memory error on the G-stage leaf read.
    g = GPA_WIDTH'('h0_2600_0000);
    h_map(tgt(7), g, PA_WIDTH'('h0_8141_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1410, F_URWXAD, 2'b00, 1'b0));
    err_pa  = W.g_slot(g[GPA_WIDTH-1:12], 0);
    err_arm = 1'b1;
    W.jr_fault(tgt(7), IFU_FAULT_ACCESS, hnd(7));
    W.mixed(2);
    // 8 cause 1: PMP denies the read of a G-stage table page.
    g = GPA_WIDTH'('h0_2800_0000);
    h_map(tgt(8), g, PA_WIDTH'('h0_8142_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1420, F_URWXAD, 2'b00, 1'b0));
    a = W.g_slot(g[GPA_WIDTH-1:12], 0);
    pmp_page(0, a, 3'b000);
    W.jr_fault(tgt(8), IFU_FAULT_ACCESS, hnd(8));
    W.mixed(2);
    // 9 kind 00 on GUEST PAGE 0, at a non-zero offset (BP-124). The VS
    //   leaf maps the target to GPA page 0, whose G-stage leaf is
    //   written invalid here; fault_gpa is the offset alone. Under
    //   MMU-30 a GPA of 0 was left 0, the collision of BP-123 risk 1.
    begin
      logic [VA_WIDTH-1:0] t9;
      t9 = tgt(9) + VA_WIDTH'('h7A4);
      W.wr64(W.g_slot('0, 0), 64'd0);
      W.wr64(W.vs_slot(t9, 0), W.mk_pte(44'h0, PTE_LEAF, 2'b00, 1'b0));
      W.jr_gfault(t9, FAULT_GPA_WIDTH'(t9[11:0]), 2'b00, hnd(9));
      W.mixed(2);
    end
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("all ten faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 10);
  endtask

  // ---- Svnapot, single stage: one walk serves the 64 KiB page ----------
  task automatic p_pt_napot_s();
    logic [VA_WIDTH-1:0] n;
    logic [PA_WIDTH-1:0] pa;
    tname = "pt_napot_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    n  = VA_WIDTH'('h0_8010_0000);
    pa = PA_WIDTH'('h0_8150_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.s_slot(n + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(pa[PA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.vmap[n[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        pa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    walk_lo = n[VA_WIDTH-1:12];
    walk_hi = n[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    run_at(n + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h100));
    run_at(n + VA_WIDTH'('h5010), PC_C + VA_WIDTH'('h200));
    run_at(n + VA_WIDTH'('hF030), PC_C + VA_WIDTH'('h300));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("one walk for three pages of the 64 KiB page (%0d)",
                  n_walk_rng), n_walk_rng == 1);
  endtask

  // ---- Svnapot and MMU-27, two stage ------------------------------------
  task automatic p_pt_napot_h();
    logic [VA_WIDTH-1:0]  va;
    logic [GPA_WIDTH-1:0] ga;
    logic [PA_WIDTH-1:0]  sa;
    tname = "pt_napot_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    map_ch();
    // A: VS 4 KiB leaves into a G-stage 64 KiB NAPOT page. Each 4 KiB
    // page walks (the smaller size wins, MMU-27).
    va = VA_WIDTH'('h0_8010_0000);
    ga = GPA_WIDTH'('h0_3000_0000);
    sa = PA_WIDTH'('h0_8150_0000);
    for (int i = 0; i < 16; i++)
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(napot(44'(sa[PA_WIDTH-1:12])), F_URWXAD, 2'b00, 1'b1));
    for (int i = 0; i < 16; i += 3) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(44'(ga[GPA_WIDTH-1:12]) + 44'(i), PTE_LEAF, 2'b00, 1'b0));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    walk_lo = va[VA_WIDTH-1:12];
    walk_hi = va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h100));
    run_at(va + VA_WIDTH'('h3010), PC_C + VA_WIDTH'('h140));
    // B: a VS 64 KiB NAPOT page over G-stage 4 KiB leaves.
    va = VA_WIDTH'('h0_8020_0000);
    ga = GPA_WIDTH'('h0_3010_0000);
    sa = PA_WIDTH'('h0_8160_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(ga[GPA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(44'(sa[PA_WIDTH-1:12]) + 44'(i), F_URWXAD, 2'b00, 1'b0));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h180));
    run_at(va + VA_WIDTH'('h7010), PC_C + VA_WIDTH'('h1C0));
    // C: NAPOT at both stages: 64 KiB, one walk for the page.
    va = VA_WIDTH'('h0_8030_0000);
    walk2_lo = va[VA_WIDTH-1:12];
    walk2_hi = va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(16);
    ga = GPA_WIDTH'('h0_3020_0000);
    sa = PA_WIDTH'('h0_8170_0000);
    for (int i = 0; i < 16; i++) begin
      W.wr64(W.vs_slot(va + VA_WIDTH'(i * 'h1000), 0),
             W.mk_pte(napot(44'(ga[GPA_WIDTH-1:12])), PTE_LEAF, 2'b00, 1'b1));
      W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(i), 0),
             W.mk_pte(napot(44'(sa[PA_WIDTH-1:12])), F_URWXAD, 2'b00, 1'b1));
      W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(i)] =
        sa[PA_WIDTH-1:12] + PPN_WIDTH'(i);
    end
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h200));
    run_at(va + VA_WIDTH'('h9010), PC_C + VA_WIDTH'('h240));
    // D: a VS 2 MiB leaf over a G-stage 4 KiB leaf.
    va = VA_WIDTH'('h0_8060_0000);
    ga = GPA_WIDTH'('h0_3040_0000);
    sa = PA_WIDTH'('h0_8180_3000);
    W.wr64(W.vs_slot(va, 1), W.mk_pte(44'(ga >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.wr64(W.g_slot(ga[GPA_WIDTH-1:12] + (GPA_WIDTH-12)'(5), 0),
           W.mk_pte(44'(sa >> 12), F_URWXAD, 2'b00, 1'b0));
    W.vmap[va[VA_WIDTH-1:12] + (VA_WIDTH-12)'(5)] = sa[PA_WIDTH-1:12];
    run_at(va + VA_WIDTH'('h5010), PC_C + VA_WIDTH'('h280));
    // E: a VS 4 KiB leaf over a G-stage 2 MiB leaf.
    va = VA_WIDTH'('h0_8080_0000);
    ga = GPA_WIDTH'('h0_3080_7000);
    sa = PA_WIDTH'('h0_81A0_0000);
    W.wr64(W.vs_slot(va, 0), W.mk_pte(44'(ga >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.wr64(W.g_slot(ga[GPA_WIDTH-1:12], 1),
           W.mk_pte(44'(sa[PA_WIDTH-1:12]), F_URWXAD, 2'b00, 1'b0));
    W.vmap[va[VA_WIDTH-1:12]] = sa[PA_WIDTH-1:12] + PPN_WIDTH'(7);
    run_at(va + VA_WIDTH'('h10), PC_C + VA_WIDTH'('h2C0));
    // The A region again: a second page of A walks again (4 KiB size),
    // the C region's second page did not (64 KiB): counted below.
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("G-stage NAPOT under VS 4 KiB: two walks (%0d)",
                  n_walk_rng), n_walk_rng == 2);
    chk($sformatf("NAPOT at both stages: one walk for two pages (%0d)",
                  n_walk_rng2), n_walk_rng2 == 1);
  endtask


  // ---- reserved encodings and PBMTE, single stage ------------------------
  // Every reserved Svnapot encoding (N set with PPN[3:0] other than
  // 1000, N on a superpage, N on a non-leaf), PBMT 3, PBMT on a
  // non-leaf; then, after a CSR write clears menvcfg.PBMTE, a leaf with
  // PBMT NC. Each is a page fault, cause 12.
  task automatic p_pt_rsv_s();
    int                  k;
    logic [VA_WIDTH-1:0] t;
    tname = "pt_rsv_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    k = 0;
    for (int lo = 0; lo < 16; lo++) begin
      if (lo == 8) continue;
      t = VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      W.wr64(W.s_slot(t, 0),
             W.mk_pte({40'h0_0000_8142, 4'(lo)}, PTE_LEAF, 2'b00, 1'b1));
      W.jr_fault(t, IFU_FAULT_PAGE, hnd(k));
      W.mixed(1);
      k++;
    end
    // N on a 2 MiB leaf.
    W.wr64(W.s_slot(tgt(1), 1), W.mk_pte(44'h8_1608, PTE_LEAF, 2'b00, 1'b1));
    W.jr_fault(tgt(1), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // N on a non-leaf.
    W.wr64(W.s_slot(tgt(2), 1), W.mk_pte(44'h8_F108, PTE_PTR, 2'b00, 1'b1));
    W.jr_fault(tgt(2), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // PBMT 3 on a leaf.
    W.wr64(W.s_slot(tgt(3), 0), W.mk_pte(44'h8_1430, PTE_LEAF, 2'd3, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // PBMT on a non-leaf.
    W.wr64(W.s_slot(tgt(4), 1), W.mk_pte(44'h8_F110, PTE_PTR, 2'd1, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // menvcfg.PBMTE cleared: PBMT NC on a leaf is reserved.
    W.csr_env(1'b0, 1'b0, 1'b0, 1'b1);
    W.mixed(1);
    W.wr64(W.s_slot(tgt(5), 0), W.mk_pte(44'h8_1450, PTE_LEAF, 2'd1, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("all %0d faults reached decode (%0d)", k, n_fault_ok),
        n_fault_ok == k);
    chk($sformatf("the CSR write retired (%0d)", n_csrw), n_csrw == 1);
  endtask

  // ---- reserved encodings and PBMTE, two stage ----------------------------
  // At the VS-stage every reserved Svnapot encoding and PBMT 3 is a page
  // fault, 12; at the G-stage the same are guest-page faults, 20, kind
  // 00 with the GPA. Then henvcfg.PBMTE clear makes a VS PBMT a page
  // fault, and menvcfg.PBMTE clear a G-stage PBMT a guest-page fault.
  task automatic p_pt_rsv_h();
    int                   k;
    logic [VA_WIDTH-1:0]  t;
    logic [GPA_WIDTH-1:0] g;
    tname = "pt_rsv_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    map_ch();
    k = 0;
    for (int lo = 0; lo < 16; lo++) begin
      if (lo == 8) continue;
      // VS-stage N reserved.
      t = VA_WIDTH'('h0_8040_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      W.wr64(W.vs_slot(t, 0),
             W.mk_pte({40'h0_0000_0123, 4'(lo)}, PTE_LEAF, 2'b00, 1'b1));
      W.jr_fault(t, IFU_FAULT_PAGE, hnd(k++));
      W.mixed(1);
      // G-stage N reserved.
      t = VA_WIDTH'('h0_8060_0000) + VA_WIDTH'(lo * 'h1000) + VA_WIDTH'('h10);
      g = GPA_WIDTH'('h0_3000_0000) + GPA_WIDTH'(lo * 'h1000);
      h_map(t, g, PA_WIDTH'('h0_8150_0000),
            W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
            W.mk_pte({40'h0_0000_8150, 4'(lo)}, F_URWXAD, 2'b00, 1'b1));
      W.jr_gfault(t, FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
      W.mixed(1);
    end
    // VS PBMT 3.
    W.wr64(W.vs_slot(tgt(3), 0), W.mk_pte(44'h0_0124, PTE_LEAF, 2'd3, 1'b0));
    W.jr_fault(tgt(3), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // G PBMT 3.
    g = GPA_WIDTH'('h0_3100_0000);
    h_map(tgt(4), g, PA_WIDTH'('h0_8151_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1510, F_URWXAD, 2'd3, 1'b0));
    W.jr_gfault(tgt(4),
                FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
    W.mixed(1);
    // henvcfg.PBMTE clear: a VS PBMT NC is reserved, menvcfg's stays set.
    W.csr_env(1'b0, 1'b0, 1'b1, 1'b0);
    W.mixed(1);
    W.wr64(W.vs_slot(tgt(5), 0), W.mk_pte(44'h0_0125, PTE_LEAF, 2'd1, 1'b0));
    W.jr_fault(tgt(5), IFU_FAULT_PAGE, hnd(k++));
    W.mixed(1);
    // menvcfg.PBMTE clear: a G-stage PBMT NC is reserved.
    W.csr_env(1'b0, 1'b0, 1'b0, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_3200_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8152_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1520, F_URWXAD, 2'd1, 1'b0));
    W.jr_gfault(tgt(6),
                FAULT_GPA_WIDTH'(g | GPA_WIDTH'('h10)), 2'b00, hnd(k++));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(60000);
    chk($sformatf("all %0d faults reached decode (%0d)", k, n_fault_ok),
        n_fault_ok == k);
    chk($sformatf("two CSR writes retired (%0d)", n_csrw), n_csrw == 2);
  endtask

  // ---- Svade and Svadu, single stage --------------------------------------
  // menvcfg.ADUE clear: a leaf with A clear faults (Svade). After a CSR
  // write sets it, the walker sets A by compare and swap and the fetch
  // proceeds; then the memory model sets A in a PTE between the walk's
  // read and its CAS (WM-11), the CAS fails and the walk restarts.
  task automatic p_pt_ad_s();
    logic [PA_WIDTH-1:0] a1;
    logic [PA_WIDTH-1:0] a2;
    tname = "pt_ad_s";
    $display("-- %s --", tname);
    reset_all(1'b1);
    map_ch();
    W.wr64(W.s_slot(tgt(0), 0),
           W.mk_pte(44'h8_1400, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.mixed(1);
    W.csr_env(1'b1, 1'b0, 1'b1, 1'b1);
    W.mixed(1);
    a1 = W.s_slot(tgt(1), 0);
    W.wr64(a1, W.mk_pte(44'h8_1410, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.vmap[tgt(1)[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1410);
    run_at(tgt(1), hnd(1));
    a2 = W.s_slot(tgt(2), 0);
    W.wr64(a2, W.mk_pte(44'h8_1420, PTE_LEAF & 8'hBF, 2'b00, 1'b0));
    W.vmap[tgt(2)[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1420);
    chg_arm = 1'b1;
    chg_pa  = a2;
    chg_val = W.mk_pte(44'h8_1420, PTE_LEAF, 2'b00, 1'b0);
    run_at(tgt(2), hnd(2));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk("Svade: the A-clear leaf faulted", n_fault_ok == 1);
    chk("Svadu: the walker set A in memory",
        W.rd64(a1) == W.mk_pte(44'h8_1410, (PTE_LEAF & 8'hBF) | 8'h40,
                               2'b00, 1'b0));
    chk($sformatf({"WM-11: the PTE changed before the CAS (%0d) and ",
                   "the walk restarted"}, n_pw_chg),
        (n_pw_chg == 1) && (n_pw_cas == 2));
  endtask

  // ---- Svade and Svadu, two stage -------------------------------------------
  task automatic p_pt_ad_h();
    logic [GPA_WIDTH-1:0] g;
    logic [GPA_WIDTH-1:0] tg;
    logic [PA_WIDTH-1:0]  gl;
    logic [PA_WIDTH-1:0]  vl;
    logic [PA_WIDTH-1:0]  gl5;
    logic [PA_WIDTH-1:0]  vl1;
    logic [PA_WIDTH-1:0]  gl1;
    tname = "pt_ad_h";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_menv_adue(1'b1);
    csr_henv_adue(1'b1);
    map_ch();
    // 1 (h 1, m 1): the VS update writes through the G-stage and sets
    // the G-stage D of the VS table page (MMU-8a), then executes.
    g = GPA_WIDTH'('h0_2000_0000);
    h_map(tgt(1), g, PA_WIDTH'('h0_8140_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1400, F_URWXAD, 2'b00, 1'b0));
    tg  = vs_l0_gpa(tgt(1));
    gl1 = W.g_slot(tg[GPA_WIDTH-1:12], 0);
    W.wr64(gl1, W.mk_pte(44'(W.g2s(tg) >> 12), 8'h5F, 2'b00, 1'b0)); // D clear
    vl1 = W.vs_slot(tgt(1), 0);
    run_at(tgt(1), hnd(1));
    // 2 (h 1, m 1): the G-stage leaf of the VS table page grants no
    // write: guest-page fault, kind 10.
    g = GPA_WIDTH'('h0_2200_0000);
    h_map(tgt(2), g, PA_WIDTH'('h0_8141_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1410, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(2));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'hDB, 2'b00, 1'b0));
    W.jr_gfault(tgt(2),
                FAULT_GPA_WIDTH'(tg + GPA_WIDTH'(8 * tgt(2)[20:12])),
                2'b10, hnd(2));
    W.mixed(1);
    // 3 (h 1 written, m 0). SYS-001: henvcfg.ADUE reads 0 while
    // menvcfg.ADUE is 0 (csr_decisions.md CSR-5), so both stages are
    // Svade and the VS leaf's clear A is a page fault, 12. Until SYS-001
    // the walker was given henvcfg.ADUE 1 here (a VS-stage Svadu over a
    // G-stage Svade, which no CSR write can produce) and the case
    // expected the G-stage D fault of the VS update, kind 10. The G leaf
    // of the VS table page is still written with D clear.
    W.csr_env(1'b0, 1'b1, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2400_0000);
    h_map(tgt(3), g, PA_WIDTH'('h0_8142_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1420, F_URWXAD, 2'b00, 1'b0));
    tg = vs_l0_gpa(tgt(3));
    W.wr64(W.g_slot(tg[GPA_WIDTH-1:12], 0),
           W.mk_pte(44'(W.g2s(tg) >> 12), 8'h5F, 2'b00, 1'b0));       // D clear
    W.jr_fault(tgt(3), IFU_FAULT_PAGE, hnd(3));
    W.mixed(1);
    // 4, 5 (h 0, m 1): the VS-stage is Svade, the G-stage Svadu.
    W.csr_env(1'b1, 1'b0, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2600_0000);
    h_map(tgt(4), g, PA_WIDTH'('h0_8143_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1430, F_URWXAD, 2'b00, 1'b0));
    W.jr_fault(tgt(4), IFU_FAULT_PAGE, hnd(4));
    W.mixed(1);
    g   = GPA_WIDTH'('h0_2800_0000);
    h_map(tgt(5), g, PA_WIDTH'('h0_8144_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1440, 8'h9F, 2'b00, 1'b0));                  // A clear
    gl5 = W.g_slot(g[GPA_WIDTH-1:12], 0);
    run_at(tgt(5), hnd(5));
    // 6 (h 1, m 1): the VS leaf changes before its CAS (WM-11).
    W.csr_env(1'b1, 1'b1, 1'b1, 1'b1);
    W.mixed(1);
    g = GPA_WIDTH'('h0_2A00_0000);
    h_map(tgt(6), g, PA_WIDTH'('h0_8145_0000),
          W.mk_pte(44'(g >> 12), PTE_LEAF & 8'hBF, 2'b00, 1'b0),
          W.mk_pte(44'h8_1450, F_URWXAD, 2'b00, 1'b0));
    vl      = W.vs_slot(tgt(6), 0);
    chg_arm = 1'b1;
    chg_pa  = vl;
    chg_val = W.mk_pte(44'(g >> 12), PTE_LEAF, 2'b00, 1'b0);
    run_at(tgt(6), hnd(6));
    warm_e = W.ne + 1;
    end_prog(60000);
    chk($sformatf("three faults (%0d)", n_fault_ok), n_fault_ok == 3);
    chk("the VS update set the VS leaf's A",
        W.rd64(vl1)[6] == 1'b1);
    chk("and the G-stage D of its table page",
        W.rd64(gl1)[7] == 1'b1);
    chk("G-stage Svadu set the code page's G leaf A",
        W.rd64(gl5)[6] == 1'b1);
    chk($sformatf("WM-11 restart (%0d)", n_pw_chg), n_pw_chg == 1);
  endtask

  // ---- an ITLB invalidate while a walk is in progress ---------------------
  // ITLB-14, IL-13, IL-14: the walk completes and is answered, the ITLB
  // installs nothing from it, and the next lookup walks again.
  task automatic p_pt_inv();
    tname = "pt_inv";
    $display("-- %s --", tname);
    reset_all(1'b1);
    pw_lat_min = 10;
    pw_lat_max = 10;
    map_ch();
    W.map4k(tgt(1) - VA_WIDTH'('h10), PA_WIDTH'('h0_8140_0000));
    walk_lo   = tgt(1)[VA_WIDTH-1:12];
    walk_hi   = tgt(1)[VA_WIDTH-1:12] + (VA_WIDTH-12)'(1);
    inv_watch = 1'b1;
    inv_vpn   = tgt(1)[VA_WIDTH-1:12];
    run_at(tgt(1), hnd(1));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf({"the invalidate fired while the walker was walking ",
                   "(%0d of %0d)"}, n_inv_busy, n_inv_fired),
        (n_inv_fired == 1) && (n_inv_busy == 1));
    chk($sformatf("the page was walked again (%0d walks)", n_walk_rng),
        n_walk_rng >= 2);
  endtask


  // =================================================================
  // BP-123, Problem 5: the RVA23 extensions that reach fetch and
  // decode. Every Zcb encoding, every C.MOP.n (Zcmop), every MOP.R.n
  // and MOP.RR.n (Zimop) and the three Zicbop prefetches, through the
  // expander, predecode, the ibuf and decode. A 16-bit encoding's
  // expected expansion is the LLVM oracle's (ifu/tb/
  // ifu_rvc_exp_oracle.hex, BP-117), not this file's; decode must not
  // raise illegal and must give the named operation; predecode must
  // class none of them as a control transfer.
  // =================================================================
  logic [39:0] rvc_orc [0:65535];

  task automatic zc(input logic [15:0] c, input alu_op_t op);
    W.put_hw(W.wp, c);
    W.add_ex(W.wp, rvc_orc[c][31:0], 1'b1, NO_BRANCH, 1'b0, '0);
    W.ex[W.ne-1].aluop = int'(op);
    W.wp = W.wp + VA_WIDTH'(2);
  endtask

  task automatic z32(input logic [31:0] w, input alu_op_t op);
    W.i32(w);
    W.ex[W.ne-1].aluop = int'(op);
  endtask

  task automatic p_zstar();
    int n_zcb;
    int n_cls;
    begin_prog("zstar");
    $readmemh("../ifu/tb/ifu_rvc_exp_oracle.hex", rvc_orc);
    W.mixed(2);
    n_zcb = 0;
    n_cls = 0;
    // Zcb. c.lbu, c.lhu, c.lh, c.sb, c.sh (quadrant 0); c.zext.b,
    // c.sext.b, c.zext.h, c.sext.h, c.zext.w, c.not, c.mul (quadrant 1).
    for (int x = 0; x < 256; x++) begin           // rs1', uimm, rd'/rs2'
      logic [2:0] r1;
      logic [1:0] ui;
      logic [2:0] r2;
      r1 = x[7:5];
      ui = x[4:3];
      r2 = x[2:0];
      zc({6'b100000, r1, ui, r2, 2'b00}, ALU_LBU);
      zc({6'b100010, r1, ui, r2, 2'b00}, ALU_SB);
      n_zcb += 2;
      if (!ui[1]) begin
        zc({6'b100001, r1, 1'b0, ui[0], r2, 2'b00}, ALU_LHU);
        zc({6'b100001, r1, 1'b1, ui[0], r2, 2'b00}, ALU_LH);
        zc({6'b100011, r1, 1'b0, ui[0], r2, 2'b00}, ALU_SH);
        n_zcb += 3;
      end
    end
    for (int r = 0; r < 8; r++) begin
      zc({6'b100111, 3'(r), 5'b11000, 2'b01}, ALU_ANDI);    // c.zext.b
      zc({6'b100111, 3'(r), 5'b11001, 2'b01}, ALU_SEXTB);
      zc({6'b100111, 3'(r), 5'b11010, 2'b01}, ALU_ZEXTH);
      zc({6'b100111, 3'(r), 5'b11011, 2'b01}, ALU_SEXTH);
      zc({6'b100111, 3'(r), 5'b11100, 2'b01}, ALU_ADDUW);   // c.zext.w
      zc({6'b100111, 3'(r), 5'b11101, 2'b01}, ALU_XOR);     // c.not
      n_zcb += 6;
      for (int r2 = 0; r2 < 8; r2++) begin
        zc({6'b100111, 3'(r), 2'b10, 3'(r2), 2'b01}, ALU_MUL);
        n_zcb++;
      end
    end
    for (int e = 0; e < W.ne; e++) begin
      logic [15:0] c;
      c = {W.rd8(W.va2pa(W.ex[e].pc) + PA_WIDTH'(1)),
           W.rd8(W.va2pa(W.ex[e].pc))};
      if (W.ex[e].rvc && (W.ex[e].aluop >= 0) && (rvc_orc[c][39:32] == 8'd1))
        n_cls++;
    end
    // Zcmop: C.MOP.n, n = 1, 3, ..., 15: c.lui's space with rd = n,
    // nzimm 0. The oracle's class 5: the canonical NOP.
    for (int n = 1; n < 16; n += 2)
      zc({3'b011, 1'b0, 5'(n), 5'b00000, 2'b01}, ALU_ADD);
    // Zimop: MOP.R.n, n = 0..31, and MOP.RR.n, n = 0..7, rd a0, rs1 a1,
    // rs2 a2: write zero to rd.
    for (int n = 0; n < 32; n++)
      z32({1'b1, 1'(n >> 4), 2'b00, 2'(n >> 2), 4'b0111, 2'(n), 5'd11,
           3'b100, 5'd10, 7'b1110011}, ALU_MOP);
    for (int n = 0; n < 8; n++)
      z32({1'b1, 1'(n >> 2), 2'b00, 2'(n), 1'b1, 5'd12, 5'd11, 3'b100,
           5'd10, 7'b1110011}, ALU_MOP);
    // Zicbop: prefetch.i, .r, .w 64(a1) (LLVM's words): the ORI HINT.
    z32(32'h0405_E013, ALU_OR);
    z32(32'h0415_E013, ALU_OR);
    z32(32'h0435_E013, ALU_OR);
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(40000);
    chk($sformatf("every Zcb encoding ran (%0d)", n_zcb), n_zcb == 1008);
    chk($sformatf("each expansion is the LLVM oracle's, class 1 (%0d)", n_cls),
        n_cls == 1008);
  endtask


  // ---- the other two vsatp / hgatp combinations, end to end -------------
  // G-stage only (vsatp Bare, hgatp Sv39x4): the fetch address is the
  // GPA, 41 bits (FE-19, MMU-20), and the walker returns the G-stage
  // leaf; the ITLB's VS-level permission rule has no leaf to read
  // (ITLB-16, fixed by BP-123). Code runs at a GPA with bit 40 set,
  // and an unmapped GPA is a guest-page fault, kind 00.
  task automatic p_pt_gonly();
    logic [VA_WIDTH-1:0] hi;
    tname = "pt_gonly";
    $display("-- %s --", tname);
    reset_all(1'b1);
    set_h2();
    csr_vsatp_mode(CSR_SATP_MODE_BARE);
    W.vmap.delete();

    W.g_map(RESET_VECTOR[VA_WIDTH-1:12], PA_WIDTH'(RESET_VECTOR),
            W.mk_pte(44'(RESET_VECTOR >> 12), F_URWXAD, 2'b00, 1'b0));
    W.vmap[RESET_VECTOR[VA_WIDTH-1:12]] = PPN_WIDTH'(RESET_VECTOR >> 12);
    W.g_map(PC_C[VA_WIDTH-1:12], PA_C, W.mk_pte(44'(PA_C >> 12), F_URWXAD,
                                               2'b00, 1'b0));
    W.vmap[PC_C[VA_WIDTH-1:12]] = PA_C[PA_WIDTH-1:12];
    W.g_map(PC_H[VA_WIDTH-1:12], PA_H, W.mk_pte(44'(PA_H >> 12), F_URWXAD,
                                               2'b00, 1'b0));
    W.vmap[PC_H[VA_WIDTH-1:12]] = PA_H[PA_WIDTH-1:12];
    hi = VA_WIDTH'('h100_8000_3000);                // GPA bit 40
    W.g_map(hi[VA_WIDTH-1:12], PA_WIDTH'('h0_8145_0000),
            W.mk_pte(44'h8_1450, F_URWXAD, 2'b00, 1'b0));
    W.vmap[hi[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1450);
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(4);
    run_at(hi + VA_WIDTH'('h20), PC_C + VA_WIDTH'('h100));
    W.jr_gfault(VA_WIDTH'('h0_8070_0010),
                FAULT_GPA_WIDTH'(GPA_WIDTH'('h0_8070_0010)), 2'b00,
                hnd(1));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("the guest-page fault reached decode (%0d)", n_fault_ok),
        n_fault_ok == 1);
  endtask

  // VS-stage only (vsatp Sv39, hgatp Bare): a GPA is the SPA. A VS leaf
  // whose PPN names an address above PA_WIDTH is then an access fault
  // (MMU-28 for a supervisor physical page; there is no G-stage to give
  // a guest-page fault), and an invalid leaf a page fault.
  task automatic p_pt_vsonly();
    tname = "pt_vsonly";
    $display("-- %s --", tname);
    reset_all(1'b1);
    W.h2     = 1'b1;
    W.g_bare = 1'b1;
    W.vs_root = W.vs_alloc();
    csr_tb_pkg::set_v(1'b1);
    csr_tb_pkg::set_priv(CSR_PRV_S);
    csr_satp_mode(CSR_SATP_MODE_BARE);
    csr_wr_vsatp(CSR_SATP_MODE_SV39, ASID_WIDTH'(1),
                 44'(W.vs_root >> 12));
    // hgatp Bare with VMID 3; its PPN is left as it was (0).
    csr_hgatp_mode_vmid(CSR_HGATP_MODE_BARE, VMID_WIDTH'(3));

    W.wr64(W.vs_slot(RESET_VECTOR, 0),
           W.mk_pte(44'(RESET_VECTOR >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[RESET_VECTOR[VA_WIDTH-1:12]] = PPN_WIDTH'(RESET_VECTOR >> 12);
    W.wr64(W.vs_slot(PC_C, 0),
           W.mk_pte(44'(PA_C >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[PC_C[VA_WIDTH-1:12]] = PA_C[PA_WIDTH-1:12];
    W.wr64(W.vs_slot(PC_H, 0),
           W.mk_pte(44'(PA_H >> 12), PTE_LEAF, 2'b00, 1'b0));
    W.vmap[PC_H[VA_WIDTH-1:12]] = PA_H[PA_WIDTH-1:12];
    W.wp = RESET_VECTOR;
    W.mixed(3);
    W.jal(5'd0, PC_C);
    W.mixed(4);
    W.wr64(W.vs_slot(tgt(1), 0),
           W.mk_pte(44'h100_8140, PTE_LEAF, 2'b00, 1'b0));
    W.jr_fault(tgt(1), IFU_FAULT_ACCESS, hnd(1));
    W.mixed(2);
    W.wr64(W.vs_slot(tgt(2), 0), W.mk_pte(44'h8_1410, 8'hC5, 2'b00, 1'b0));
    W.jr_fault(tgt(2), IFU_FAULT_PAGE, hnd(2));
    W.mixed(2);
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("both faults reached decode (%0d)", n_fault_ok),
        n_fault_ok == 2);
  endtask

  // =================================================================
  // ---- BP-124: U against the privilege before A (MMU-8c), and a held
  // fault is the answer only at its own privilege (ITLB-10b) ----------
  // Under Svadu (menvcfg.ADUE set), single stage:
  //   0  at U, a fetch from a U-clear page with A clear: cause 12, the
  //      trap taken to S, A still clear in memory
  //   1  at S, a fetch from a U-set page with A clear: cause 12, A
  //      still clear
  //   2  at U, the block after a JAL that ends the U code page falls
  //      into page p2 (U clear, A clear) on the wrong path: the ITLB
  //      walks it at U and the walk faults; the predecode redirect has
  //      flushed the block, so the fault is held and not collected.
  //      After an ecall to S, a fetch at S of p2 must drop the held U
  //      fault, walk at S and execute; that walk sets p2's A
  // The U code page is U set with A and D set.
  localparam logic [VA_WIDTH-1:0] PC_U = VA_WIDTH'('h0_8003_0000);
  localparam logic [PA_WIDTH-1:0] PA_U = PA_WIDTH'('h0_8170_0000);

  task automatic p_pt_upriv();
    logic [PA_WIDTH-1:0] a0;
    logic [PA_WIDTH-1:0] a1;
    logic [PA_WIDTH-1:0] a2;
    logic [VA_WIDTH-1:0] p2;
    logic [63:0]         l0;
    logic [63:0]         l1;
    logic [63:0]         l2;
    tname = "pt_upriv";
    $display("-- %s --", tname);
    reset_all(1'b1);
    csr_menv_adue(1'b1);                             // Svadu
    map_ch();
    W.wr64(W.s_slot(PC_U, 0), W.mk_pte(44'(PA_U >> 12), PTE_LEAF | 8'h10,
                                       2'b00, 1'b0));
    W.vmap[PC_U[VA_WIDTH-1:12]] = PA_U[PA_WIDTH-1:12];
    p2 = PC_U + VA_WIDTH'('h1000);
    a0 = W.s_slot(tgt(0), 0);
    a1 = W.s_slot(tgt(1), 0);
    a2 = W.s_slot(p2, 0);
    l0 = W.mk_pte(44'h8_1400, PTE_LEAF & 8'hBF, 2'b00, 1'b0);        // A
    l1 = W.mk_pte(44'h8_1410, (PTE_LEAF & 8'hBF) | 8'h10, 2'b00, 1'b0);
    l2 = W.mk_pte(44'h8_1420, PTE_LEAF & 8'hBF, 2'b00, 1'b0);
    W.wr64(a0, l0);
    W.wr64(a1, l1);
    W.wr64(a2, l2);
    W.vmap[p2[VA_WIDTH-1:12]] = PPN_WIDTH'(24'h8_1420);
    up_vpn = p2[VA_WIDTH-1:12];
    // 0: to U, then a fetch from the U-clear page.
    W.sret_to(PC_U + VA_WIDTH'('h100), 2'd0);
    W.mixed(2);
    W.jr_fault(tgt(0), IFU_FAULT_PAGE, hnd(0));
    W.ex[W.ne-1].npriv = 1;                          // the trap, to S
    W.mixed(2);
    // 1: at S, a fetch from the U-set page.
    W.jr_fault(tgt(1), IFU_FAULT_PAGE, hnd(1));
    W.mixed(2);
    // 2: to U at the last 32-byte block of the U page, which ends with
    // a JAL back into the page; the fall-through block is p2.
    W.sret_to(PC_U + VA_WIDTH'('hFE0), 2'd0);
    for (int i = 0; i < 7; i++) W.i32(ADDI_T0);
    W.jal(5'd0, PC_U + VA_WIDTH'('h200));
    W.mixed(2);
    W.ecall(hnd(2));
    W.ex[W.ne-1].npriv = 1;                          // to S
    W.mixed(2);
    run_at(p2 + VA_WIDTH'('h10), hnd(3));
    warm_e = W.ne + 1;
    end_prog(30000);
    chk($sformatf("both privilege faults reached decode (%0d)",
                  n_fault_ok), n_fault_ok == 2);
    chk("0: a U fetch from a U-clear page left A clear",
        W.rd64(a0) == l0);
    chk("1: an S fetch from a U-set page left A clear",
        W.rd64(a1) == l1);
    chk($sformatf("2: p2 was walked at U and faulted (%0d)", n_up_wu_flt),
        n_up_wu_flt >= 1);
    chk($sformatf("2: the held U fault was dropped at S (%0d)", n_up_drop),
        n_up_drop >= 1);
    chk($sformatf("2: p2 was walked at S and hit (%0d)", n_up_ws_hit),
        n_up_ws_hit == 1);
    chk("2: the S walk set p2's A", W.rd64(a2) == (l2 | 64'h40));
  endtask

  // Program selection. +PROG=<name> runs one program; without it,
  // every program runs.
  // =================================================================
  task automatic run_prog(input string nm);
    case (nm)
      "bare":       p_bare();
      "sv39":       p_sv39();
      "loops":      p_loops();
      "coro":       p_coro();
      "calls":      p_calls();
      "lp":         p_lp();
      "hist":       p_hist();
      "twocond":    p_twocond();
      "ftbonly":    p_ftbonly();
      "nest":       p_nest();
      "recur":      p_recur();
      "rec_undo":   p_rec_undo();
      "t0_uaon":    p_t0_uaon();
      "deep":       p_deep();
      "indir":      p_indir();
      "region":     p_region();
      "multistart": p_multistart();
      "cross":      p_cross();
      "rvc":        p_rvc();
      "misp_call":  p_misp_call();
      "jals":       p_jals();
      "fencei":     p_smc(1);
      "cboinval":   p_smc(2);
      "uc_nc":      p_uc(2'd1);
      "uc_io":      p_uc(2'd2);
      "pt_faults_s": p_pt_faults_s();
      "pt_faults_h": p_pt_faults_h();
      "pt_napot_s": p_pt_napot_s();
      "pt_napot_h": p_pt_napot_h();
      "pt_rsv_s":   p_pt_rsv_s();
      "pt_rsv_h":   p_pt_rsv_h();
      "pt_ad_s":    p_pt_ad_s();
      "pt_ad_h":    p_pt_ad_h();
      "pt_inv":     p_pt_inv();
      "zstar":      p_zstar();
      "pt_gonly":   p_pt_gonly();
      "pt_vsonly":  p_pt_vsonly();
      "pt_upriv":   p_pt_upriv();
      "init_walk":  p_init_walk();
      default: begin
        fail_cnt++;
        $display("FAIL: unknown program %s", nm);
      end
    endcase
  endtask

  string all_progs [0:38] = '{"bare", "sv39", "loops", "coro", "calls",
                              "lp", "hist", "twocond", "ftbonly", "nest",
                              "recur", "rec_undo", "t0_uaon", "deep",
                              "indir", "region",
                              "multistart", "cross", "rvc", "misp_call",
                              "jals", "fencei", "cboinval", "uc_nc",
                              "uc_io", "pt_faults_s", "pt_faults_h",
                              "pt_napot_s", "pt_napot_h", "pt_rsv_s",
                              "pt_rsv_h", "pt_ad_s", "pt_ad_h", "pt_inv",
                              "zstar", "pt_gonly", "pt_vsonly",
                              "pt_upriv", "init_walk"};

  // =================================================================
  initial begin
    string prog;
    pass_cnt = 0;
    fail_cnt = 0;
    // BP-122: one program per simulation. The mode that ran every
    // program in one simulation carried the RAM predictor tables from
    // one program into the next: the FTB array has no reset, and the
    // TAGE, ITTAGE and SC tables are filled once, at time 0, by the
    // FAST_INIT plusargs every run uses. It is removed rather than given
    // a table reset, which the RTL does not have and the testbench would
    // have to force into every RAM. sim_fe_top runs each program alone.
    if ($value$plusargs("PROG=%s", prog)) begin
      run_prog(prog);
    end else begin
      fail_cnt++;
      $display("FAIL: +PROG=<name> is required; programs:");
      foreach (all_progs[i]) $display("  %s", all_progs[i]);
    end
    $display("tb_fe_top: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt != 0) begin
      $fatal(1, "tb_fe_top: %0d checks failed", fail_cnt);
    end else begin
      $display("ALL TESTS PASSED");
      $finish;
    end
  end

  initial begin
    #30000000;
    $fatal(1, "tb_fe_top: timeout");
  end

endmodule : tb
