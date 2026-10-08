// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FTQ update converter (BP-119, TD#151, TD#150).
// ftq_bpu_interfaces.md 8, fe_decisions.md 7.2.
//
// FORMS THE PER-PREDICTOR UPDATE PAYLOADS the cluster takes, from the
// resolved-branch record ftq_resolve presents per slot. Ruled
// session-075: a module inside the FTQ, instantiated by ftq.sv, so the
// FTQ's update ports are the per-predictor types section 8 lists:
//
//   ubtb       ubtb_upd_t          valid inside the struct
//   loop_pred  lp_upd_t            lp_upd_valid_p0
//   tage       tage_upd_inp_t      tage_upd_val_u0
//   ittage     ittage_upd_inp_t    ittage_upd_val_u0
//   sc         sc_upd_inp_t        sc_upd_val_u0
//
// The FTB update (ftq_ftb_sched) and the RAS commit group (ftq_entry)
// are not formed here and are unchanged.
//
// EVERY FIELD HAS A SOURCE in bp_update_t (upd), bp_ftq_meta_t
// (upd_meta) or the fast-path entry (upd_entry). The branch PC is the
// block start plus the slot's position, formed exactly as bp_cluster
// forms it for bp_history (POS_OFFSET_BITS). The field-by-field table
// is in the BP-119 Results Capture.
//
// THE HANDSHAKE (TD#150). ftq_resolve presents, per slot, a REQUEST
// for each predictor the resolution trains (its upd_*_val). The
// cluster presents a ready per slot for each queued predictor; they
// are ANDed per predictor, so a full queue on either slot stalls both
// channels for that predictor. A slot is ACCEPTED (upd_acc) when
// every predictor it requests is ready, and only then is any of its
// predictor valids presented: the uBTB and the LP have no ready and
// apply whatever they are given, so a partial acceptance would apply
// the update twice when the backend re-presents the resolution.
//
// THE SC READY IS DIFFERENT AND IS WHY THE ORDER BELOW MATTERS. The
// cluster asserts sc_upd_rdy only in a cycle its credit arbiter grants
// SC an update, and the arbiter grants only a presented update
// (bp_cluster sc_arb_comb). So the SC valid is presented when every
// OTHER predictor the slot requests is ready -- never gated by the SC
// ready itself, which would close a combinational loop and leave both
// low -- and the slot is accepted when, in addition, SC granted it.
// tage_upd_rdy and ittage_upd_rdy are queue-not-full and depend on no
// valid.
//
// THE SC-DISABLED RULE (ftq_bpu_interfaces.md 7.2, FE-U6): when SC is
// disabled the FTQ forms no SC update, and the slot does not wait on
// the SC ready.
//
// COMBINATIONAL MODULE. clk and rstn are here for the bound
// properties only, as in ftq_resolve.
// ===================================================================
import bp_defines_pkg::*;
import bp_structs_pkg::*;

module ftq_upd_conv (
  input  logic                          clk,
  input  logic                          rstn,

  // ---- configuration ------------------------------------------------
  input  logic                          sc_enable,

  // ---- the resolved record, per slot, from ftq_resolve --------------
  input  bp_update_t                    upd       [0:NUM_PRED_SLOTS-1],
  input  bp_ftq_meta_t                  upd_meta  [0:NUM_PRED_SLOTS-1],
  input  bp_ftq_entry_t                 upd_entry [0:NUM_PRED_SLOTS-1],
  input  logic [NUM_PRED_SLOTS-1:0]     upd_ubtb_val,
  input  logic [NUM_PRED_SLOTS-1:0]     upd_lp_val,
  input  logic [NUM_PRED_SLOTS-1:0]     upd_tage_val,
  input  logic [NUM_PRED_SLOTS-1:0]     upd_ittage_val,
  input  logic [NUM_PRED_SLOTS-1:0]     upd_sc_val,

  // ---- slot accepted by every predictor it trains, to ftq_resolve --
  output logic [NUM_PRED_SLOTS-1:0]     upd_acc,

  // ---- the cluster's per-slot queue readies -------------------------
  input  logic [NUM_PRED_SLOTS-1:0]     tage_upd_rdy,
  input  logic [NUM_PRED_SLOTS-1:0]     ittage_upd_rdy,
  input  logic [NUM_PRED_SLOTS-1:0]     sc_upd_rdy,

  // ---- the per-predictor payloads, ftq_bpu_interfaces.md 8 ---------
  output ubtb_upd_t [NUM_PRED_SLOTS-1:0] ubtb_upd_u0,
  output logic [NUM_PRED_SLOTS-1:0]     lp_upd_valid_p0,
  output lp_upd_t                       lp_upd_p0
                                          [0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]     tage_upd_val_u0,
  output tage_upd_inp_t                 tage_upd_inp_u0
                                          [0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]     ittage_upd_val_u0,
  output ittage_upd_inp_t               ittage_upd_inp_u0
                                          [0:NUM_PRED_SLOTS-1],
  output logic [NUM_PRED_SLOTS-1:0]     sc_upd_val_u0,
  output sc_upd_inp_t                   sc_upd_inp_u0
                                          [0:NUM_PRED_SLOTS-1]
);

  // The SC branch_range field is PC bits 15:6 (sc_upd_inp_t).
  localparam int SC_RANGE_LO = 6;
  localparam int SC_RANGE_W  = 10;

  // TD#150: the per-slot readies ANDed per predictor.
  logic                      w_tage_rdy;
  logic                      w_ittage_rdy;
  logic                      w_sc_rdy;

  // Per slot: the SC request after the SC-disabled rule, the
  // readiness of every predictor other than SC, and the branch PC.
  logic [NUM_PRED_SLOTS-1:0] w_sc_req;
  logic [NUM_PRED_SLOTS-1:0] w_pre_ok;
  logic [VA_WIDTH-1:0]       w_br_pc [0:NUM_PRED_SLOTS-1];

  assign w_tage_rdy   = &tage_upd_rdy;
  assign w_ittage_rdy = &ittage_upd_rdy;
  assign w_sc_rdy     = &sc_upd_rdy;

  // -----------------------------------------------------------------
  // The SC valid. Reads no SC ready, see the header.
  // -----------------------------------------------------------------
  always_comb begin : sc_present
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      w_sc_req[s]      = upd_sc_val[s] & sc_enable;
      w_pre_ok[s]      = (~upd_tage_val[s]   | w_tage_rdy)
                       & (~upd_ittage_val[s] | w_ittage_rdy);
      sc_upd_val_u0[s] = w_sc_req[s] & w_pre_ok[s];
    end
  end

  // -----------------------------------------------------------------
  // Acceptance and the gated valids of every predictor but SC.
  // -----------------------------------------------------------------
  always_comb begin : accept
    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      upd_acc[s]           = w_pre_ok[s] & (~w_sc_req[s] | w_sc_rdy);
      lp_upd_valid_p0[s]   = upd_lp_val[s]     & upd_acc[s];
      tage_upd_val_u0[s]   = upd_tage_val[s]   & upd_acc[s];
      ittage_upd_val_u0[s] = upd_ittage_val[s] & upd_acc[s];
    end
  end

  // -----------------------------------------------------------------
  // The payloads. Formed whenever the slot carries a resolution, so
  // the cluster's update type decode (bp_cluster upd_br_type, which
  // reads the uBTB payload's structural bits for every predictor)
  // always sees the resolved type.
  // -----------------------------------------------------------------
  always_comb begin : payloads
    bp_br_type_e         bt;
    logic [VA_WIDTH-1:0] pt;

    for (int s = 0; s < NUM_PRED_SLOTS; s++) begin
      bt = upd[s].br_type;
      pt = '0;

      // The branch PC: block start plus the slot's position, which is
      // start-relative (ftq_bpu_interfaces.md 7.4).
      w_br_pc[s] = upd[s].pc
                 + (VA_WIDTH'(upd_entry[s].slot[s].pos) << POS_OFFSET_BITS);

      ubtb_upd_u0[s]       = '0;
      lp_upd_p0[s]         = '0;
      tage_upd_inp_u0[s]   = '0;
      ittage_upd_inp_u0[s] = '0;
      sc_upd_inp_u0[s]     = '0;

      if (upd[s].valid) begin
        // -- uBTB. The same resolved facts as the FTB update
        //    (ftq_resolve ftb_update), field for field: the uBTB and
        //    FTB update field sets mirror each other (section 8).
        ubtb_upd_u0[s].valid      = upd_ubtb_val[s] & upd_acc[s];
        ubtb_upd_u0[s].pc         = upd[s].pc;
        ubtb_upd_u0[s].is_br      = (bt == COND);
        ubtb_upd_u0[s].br_idx     = (s != 0);
        ubtb_upd_u0[s].br_taken   = upd[s].actual_taken;
        ubtb_upd_u0[s].target     = upd[s].actual_target;
        ubtb_upd_u0[s].pos        = upd_entry[s].slot[s].pos;
        ubtb_upd_u0[s].is_jmp     = (bt != COND) && (bt != NO_BRANCH);
        ubtb_upd_u0[s].jmp_target = upd[s].actual_target;
        ubtb_upd_u0[s].is_call    = (bt == DIRECT_CALL)   ||
                                    (bt == INDIRECT_CALL) ||
                                    (bt == RETURN_CALL);
        ubtb_upd_u0[s].is_ret     = (bt == RETURN) || (bt == RETURN_CALL);
        ubtb_upd_u0[s].is_jalr    = (bt == INDIRECT_NONRET) ||
                                    (bt == INDIRECT_CALL)   ||
                                    (bt == RETURN)          ||
                                    (bt == RETURN_CALL);
        ubtb_upd_u0[s].pft_addr   = upd_entry[s].pft_addr;

        // -- loop_pred. The table coordinates are the predict-time
        //    snapshot (lp_pred_t, TD#106); pc is the branch PC, which
        //    loop_pred compares the target against for a backward
        //    branch.
        lp_upd_p0[s].pc              = w_br_pc[s];
        lp_upd_p0[s].target          = upd[s].actual_target;
        lp_upd_p0[s].actual_taken    = upd[s].actual_taken;
        lp_upd_p0[s].lp_idx          = upd_meta[s].lp.lp_idx;
        lp_upd_p0[s].lp_tag          = upd_meta[s].lp.lp_tag;
        lp_upd_p0[s].lp_way          = upd_meta[s].lp.lp_way;
        lp_upd_p0[s].lp_hit          = upd_meta[s].lp.lp_hit;
        lp_upd_p0[s].lp_pred_is_loop = upd_meta[s].lp.lp_pred_is_loop;
        lp_upd_p0[s].lp_pred_taken   = upd_meta[s].lp.lp_pred_taken;
        lp_upd_p0[s].lp_age          = upd_meta[s].lp.lp_age;
        lp_upd_p0[s].lp_conf         = upd_meta[s].lp.lp_conf;
        lp_upd_p0[s].lp_past_itr     = upd_meta[s].lp.lp_past_itr;
        lp_upd_p0[s].lp_curr_itr     = upd_meta[s].lp.lp_curr_itr;
        lp_upd_p0[s].lp_curs         = upd_meta[s].lp.lp_curs;
        lp_upd_p0[s].lp_curs_v       = upd_meta[s].lp.lp_curs_v;
        lp_upd_p0[s].lp_victim       = upd_meta[s].lp.lp_victim;

        // -- TAGE. cond_mispredict is the provider's prediction
        //    against the outcome (tage_cntrl_use_update_rules.md, "the
        //    provider's prediction was not correct"): the TAGE
        //    direction in the metadata, not the final prediction,
        //    which SC or the LP may have supplied.
        tage_upd_inp_u0[s].tage_pred_meta  = upd_meta[s].tage;
        tage_upd_inp_u0[s].resolved_taken  = upd[s].actual_taken;
        tage_upd_inp_u0[s].cond_mispredict =
          (upd_meta[s].tage.tage_pred_tkn != upd[s].actual_taken);

        // -- ITTAGE. resolved_target is VA[40:1], bit 0 not stored
        //    (ftq_bpu_interfaces.md 5.2). indir_mispredict is the
        //    provider target against it, the provider named by
        //    ittage_using_primary (ittage_cntrl_ctr_update_rules.md,
        //    MIS = PT != RT); a miss supplied no target and counts as
        //    a mispredict, so an allocation can follow it.
        pt = upd_meta[s].ittage.ittage_using_primary
               ? {upd_meta[s].ittage.ittage_prm_tgt, 1'b0}
               : {upd_meta[s].ittage.ittage_alt_tgt, 1'b0};
        ittage_upd_inp_u0[s].ittage_pred_meta = upd_meta[s].ittage;
        ittage_upd_inp_u0[s].resolved_target  =
          upd[s].actual_target[VA_WIDTH-1:1];
        ittage_upd_inp_u0[s].indir_mispredict =
          !upd_meta[s].ittage.ittage_hit ||
          (pt[VA_WIDTH-1:1] != upd[s].actual_target[VA_WIDTH-1:1]);

        // -- SC. backwards_branch and branch_range describe the
        //    branch PC, as sc_upd_inp_t names them.
        sc_upd_inp_u0[s].sc_pred_meta     = upd_meta[s].sc;
        sc_upd_inp_u0[s].resolved_taken   = upd[s].actual_taken;
        sc_upd_inp_u0[s].cond_mispredict  =
          (upd_meta[s].sc.sc_pred_tkn != upd[s].actual_taken);
        sc_upd_inp_u0[s].backwards_branch =
          (upd[s].actual_target < w_br_pc[s]);
        sc_upd_inp_u0[s].branch_range     =
          w_br_pc[s][SC_RANGE_LO +: SC_RANGE_W];
      end
    end
  end

  // clk and rstn are read by the bound properties, not by this
  // module. See the header.
  logic w_unused;
  assign w_unused = clk | rstn;

endmodule : ftq_upd_conv
