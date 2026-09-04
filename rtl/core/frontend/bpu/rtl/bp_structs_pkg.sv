// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    bp_structs_pkg.sv
// DATE:    2026-05-14
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Branch predictor cluster package: types, structs.
// All BP cluster modules import this package.
// Single source of truth for BP cluster types 
// ===================================================================
`ifndef BP_STRUCTS_PKG_SV
`define BP_STRUCTS_PKG_SV

import bp_defines_pkg::*;

package bp_structs_pkg;

  // ----------------------------------------------------------------
  // Folded history struct
  // ----------------------------------------------------------------
  // All folded histories produced by bp_history and consumed by
  // TAGE, ITTAGE, and SC for index and tag computation.
  // SC ST0 (hist=0) and ST4 (IMLI) -- no folds.
  typedef struct packed {
    // -- TAGE T1
    logic [TAGE_MAX_FH-1:0]  tage_t1_idx_fh;
    logic [TAGE_MAX_FH1-1:0] tage_t1_tag_fh1;
    logic [TAGE_MAX_FH2-1:0] tage_t1_tag_fh2;
    // -- TAGE T2
    logic [TAGE_MAX_FH-1:0]  tage_t2_idx_fh;
    logic [TAGE_MAX_FH1-1:0] tage_t2_tag_fh1;
    logic [TAGE_MAX_FH2-1:0] tage_t2_tag_fh2;
    // -- TAGE T3
    logic [TAGE_MAX_FH-1:0]  tage_t3_idx_fh;
    logic [TAGE_MAX_FH1-1:0] tage_t3_tag_fh1;
    logic [TAGE_MAX_FH2-1:0] tage_t3_tag_fh2;
    // -- TAGE T4
    logic [TAGE_MAX_FH-1:0]  tage_t4_idx_fh;
    logic [TAGE_MAX_FH1-1:0] tage_t4_tag_fh1;
    logic [TAGE_MAX_FH2-1:0] tage_t4_tag_fh2;
    // -- ITTAGE IT1
    logic [IT_MAX_FH-1:0]    it_t1_idx_fh;
    logic [IT_MAX_FH1-1:0]   it_t1_tag_fh1;
    logic [IT_MAX_FH2-1:0]   it_t1_tag_fh2;
    // -- ITTAGE IT2
    logic [IT_MAX_FH-1:0]    it_t2_idx_fh;
    logic [IT_MAX_FH1-1:0]   it_t2_tag_fh1;
    logic [IT_MAX_FH2-1:0]   it_t2_tag_fh2;
    // -- ITTAGE IT3
    logic [IT_MAX_FH-1:0]    it_t3_idx_fh;
    logic [IT_MAX_FH1-1:0]   it_t3_tag_fh1;
    logic [IT_MAX_FH2-1:0]   it_t3_tag_fh2;
    // -- ITTAGE IT4
    logic [IT_MAX_FH-1:0]    it_t4_idx_fh;
    logic [IT_MAX_FH1-1:0]   it_t4_tag_fh1;
    logic [IT_MAX_FH2-1:0]   it_t4_tag_fh2;
    // -- ITTAGE IT5
    logic [IT_MAX_FH-1:0]    it_t5_idx_fh;
    logic [IT_MAX_FH1-1:0]   it_t5_tag_fh1;
    logic [IT_MAX_FH2-1:0]   it_t5_tag_fh2;
    // -- SC ST1-ST3 (one index fold each)
    logic [SC_MAX_FH-1:0]    sc_t1_idx_fh;
    logic [SC_MAX_FH-1:0]    sc_t2_idx_fh;
    logic [SC_MAX_FH-1:0]    sc_t3_idx_fh;
    // -- PHR 
    logic [PHR_WIDTH-1:0]    tage_phr;

  } bp_folded_hist_t;

  // ----------------------------------------------------------------
  // Enumerations
  // ----------------------------------------------------------------

  // Branch type encoding, 3b.
  // Used in bp_ftq_slot_t.br_type and bp_update_t.br_type.
  // RETURN excludes C.JALR, and excludes a JALR whose rd is also
  // a link register. Without that exclusion a JALR rd=x1 rs1=x1
  // would satisfy both the call and the return rule, and the
  // three-way FTB/RAS/ITTAGE split is mutually exclusive.
  // See planning/arch/ras_decisions.md section 2.
  typedef enum logic [2:0] {
    COND            = 3'b000, // conditional branch (JAL/B-type)
    DIRECT_CALL     = 3'b001, // direct call: JAL rd=x1 or x5
    INDIRECT_CALL   = 3'b010, // indirect call: JALR rd=x1 or x5
    RETURN          = 3'b011, // return: JALR/C.JR rs1=x1/x5
    INDIRECT_NONRET = 3'b100, // indirect JALR, not call, not return
    DIRECT_UNC      = 3'b101, // direct unconditional: JAL rd!=link
    NO_BRANCH       = 3'b110  // no branch in fetch block
  } bp_br_type_e;

  // Prediction source: which predictor supplied the final result.
  // Recorded in bp_ftq_slot_t.pred_src at prediction commit time.
  typedef enum logic [2:0] {
    PRED_UBTB   = 3'b000, // uBTB supplied prediction (p1)
    PRED_LOOP   = 3'b001, // loop predictor overrode uBTB (p1)
    PRED_FTB    = 3'b010, // FTB supplied prediction (p2)
    PRED_TAGE   = 3'b011, // TAGE overrode FTB direction (p2)
    PRED_SC     = 3'b100, // SC overrode TAGE direction (p3)
    PRED_ITTAGE = 3'b101, // ITTAGE supplied indirect target
    PRED_RAS    = 3'b110, // RAS supplied return target
    PRED_NONE   = 3'b111  // no prediction (uBTB miss, loop absent)
  } bp_pred_src_e;

  // SC range based chooser:
  // Recorded in sc_pred_meta_t at prediction 
  typedef enum logic [1:0] {
    CHOOSE_NONE  = 2'b00,
    CHOOSE_MED   = 2'b01,
    CHOOSE_HIGH  = 2'b10,
    CHOOSE_RSRVD = 2'b11
  } bp_sc_chooser_e;

  // Backend redirect cause, 2b. Carried on bkend_ftq_redir_cause.
  // RC_UNSPEC names NO instruction: _idx, _pos and _self are
  // meaningless on it and must not be read, and no history or RAS
  // restore is performed. It is reset and debug-mode entry.
  // See ftq_backend_interfaces.md 5 and 5.1.
  typedef enum logic [1:0] {
    RC_MISPREDICT = 2'b00, // branch resolved against the prediction
    RC_TRAP       = 2'b01, // exception or interrupt
    RC_REPLAY     = 2'b10, // pipeline replay, memory ordering
    RC_UNSPEC     = 2'b11  // no naming instruction
  } ftq_redir_cause_e;

  // BrIMLI modes, for perf analysis, 2'b00 is default
  typedef enum logic [1:0] {
    IDX_IMLI_PHR  = 2'b00, // baseline: IMLI, fall back to PHR when cold
    IDX_PHR_ONLY  = 2'b01, // force PHR always  (baseline: no IMLI at all)
    IDX_IMLI_ONLY = 2'b10, // IMLI always, no PHR substitution
    IDX_IMLI_RSRV = 2'b11  // not used
  } br_imli_mode_e;
  // ----------------------------------------------------------------
  // Sub-structs
  // ----------------------------------------------------------------

  // RAS speculative pointer snapshot stored in FTQ fast path.
  // Restored on mispredict flush to recover speculative stack
  // state. Simple circular buffer: restoring these three
  // pointers is sufficient. No push/pop replay needed.
  // RAS_PTR_BITS = $clog2(16) = 4b. Total snapshot = 12b.
  // See planning/arch/ras_decisions.md section 4.
  typedef struct packed {
    logic [RAS_PTR_BITS-1:0] tosr; // top-of-stack read pointer
    logic [RAS_PTR_BITS-1:0] tosw; // top-of-stack write pointer
    logic [RAS_PTR_BITS-1:0] bos;  // bottom-of-stack pointer
  } bp_ras_snapshot_t;

//  // SC (Statistical Corrector) predictor metadata.
//  // sc_upd_idx[3:0]: ST0-ST3 indices (4 tables, SC_MAX_IDX_WIDTH each).
//  // sc_imli_idx: ST4 (IMLI) index (SC_IMLI_INDEX_BITS = 10b).
//  // sc_upd_ctr[SC_NUM_ALL_TBLS-1:0]: counter snapshots ST0-ST4
//  //   (SC_TBL_DATA_BITS = 24b each; ST4 uses lower
//  //   SC_ST4_DATA_BITS bits only).
//  typedef struct packed {
//    logic                             sc_pred_tkn;
//    logic                             sc_override;
//    logic [3:0][SC_MAX_IDX_WIDTH-1:0] sc_upd_idx;
//    logic [SC_MAX_IDX_WIDTH-1:0]      sc_imli_idx;
//    logic [SC_NUM_ALL_TBLS-1:0][SC_MAX_DATA_WIDTH-1:0] sc_upd_ctr;
//  } bp_sc_meta_t;

  // lp_pred_t: prediction output for one loop predictor lookup.
  // Carried in the FTQ slow path; supplies the update path without
  // re-reading the table. It is also the loop predictor member of
  // bp_ftq_meta_t, so it is declared here, ahead of that struct,
  // rather than with the other loop predictor structs further down.
  // TD#106: this type replaced bp_loop_meta_t, which carried the
  // same thirteen fields in a different order and spelled two of
  // them lp_pst_itr and lp_cur_itr. Both names retired with the type.
  typedef struct packed {
    logic [LP_IDX_BITS-1:0]  lp_idx;          // set index at predict time
    logic [LP_TAG_BITS-1:0]  lp_tag;          // tag at predict time
    logic [LP_WAY_BITS-1:0]  lp_way;          // way that hit
    logic                    lp_hit;          // tag match (any confidence)
    logic                    lp_pred_is_loop; // loop predictor trusted
    logic                    lp_pred_taken;   // direction used
    logic [LP_AGE_BITS-1:0]  lp_age;          // age counter snapshot
    logic [LP_CNF_BITS-1:0]  lp_conf;         // confidence counter snapshot
    logic [LP_ITR_BITS-1:0]  lp_past_itr;     // past iteration count
    logic [LP_ITR_BITS-1:0]  lp_curr_itr;     // current iteration count
    logic [LP_ITR_BITS-1:0]  lp_curs;         // speculative cursor
    logic                    lp_curs_v;       // cursor valid
    logic [LP_WAY_BITS-1:0]  lp_victim;       // allocation target way
  } lp_pred_t;

  // TAGE prediction input bundle.
  // Carries PC and branch_id into the TAGE predictor at predict time.
  typedef struct packed {
    logic [VA_WIDTH-1:0]      pc;
    logic [FTQ_IDX_BITS-1:0]  branch_id;
  } tage_pred_inp_t;

  // TAGE prediction metadata.
  typedef struct packed {
    // Provider and alt-provider table indices and selectors
    logic [TAGE_MAX_AWIDTH-1:0]    tage_prm_idx;    // primary idx
    logic [TAGE_MAX_AWIDTH-1:0]    tage_alt_idx;    // alt-prov idx
    logic [TAGE_TBL_SEL_WIDTH-1:0] tage_prm_comp;   // primary tbl
    logic [TAGE_TBL_SEL_WIDTH-1:0] tage_alt_comp;   // alt-prov tbl
    // Usefulness and counter snapshots
    logic [TAGE_MAX_USE_WIDTH-1:0] tage_prm_useful; // primary useful
    logic [TAGE_MAX_USE_WIDTH-1:0] tage_alt_useful; // alt useful
    logic [TAGE_MAX_CTR_WIDTH-1:0] tage_prm_ctr;    // primary ctr
    logic [TAGE_MAX_CTR_WIDTH-1:0] tage_alt_ctr;    // alt ctr
    // Allocation target (new entry on miss)
    logic [TAGE_TBL_SEL_WIDTH-1:0] tage_alc_comp;   // alloc tbl
    logic [TAGE_MAX_AWIDTH-1:0]    tage_alc_idx;    // alloc idx
    logic [TAGE_MAX_DWIDTH-1:0]    tage_alc_tag;    // alloc tag
    // Prediction flags
    logic                          tage_prm_tkn;    // primary T/NT
    logic                          tage_alt_tkn;    // alt T/NT
    // Prediction confidence decode on the provider (post-mux) CTR.
    // TD#87 one-hot decode by 3b CTR:
    //   000 strong / 001 medium / 010 medium / 011 weak /
    //   100 weak   / 101 medium / 110 medium / 111 strong.
    logic                          tage_pred_strong;   // ctr 000 or 111
    logic                          tage_use_alt_on_na; // USE_ALT_ON_NA hit
    logic                          tage_using_primary; // primary supplied

    // tage_high_conf removed (TD#95); do not re-add.
    logic                          tage_pred_weak;     // ctr 011 or 100
    logic                          tage_pred_medium;   // ctr 001/010/101/110

    logic                          tage_pred_tkn;      // TAGE direction

    // Derived and convenience signals

    // tage_provider_ctr is an internal convenience only (TD#88); it is
    // not a struct field. Only tage_extd_ctr is exposed to SC.
    logic signed   [TAGE_MAX_CTR_WIDTH+1:0] tage_extd_ctr;

    // FTQ entry index appended to tage_pred_meta_t fields
    logic [FTQ_IDX_BITS-1:0]       branch_id;
  } tage_pred_meta_t;

  // TAGE update input bundle.
  // Carries tage_pred_meta_t captured at predict time plus resolved
  // direction and mispredict flag from the execute stage.
  typedef struct packed {
    tage_pred_meta_t  tage_pred_meta;
    logic             resolved_taken;
    logic             cond_mispredict;
  } tage_upd_inp_t;

  // ----------------------------------------------------------------
  // ITTAGE structs
  // ----------------------------------------------------------------

  // ITTAGE prediction input bundle.
  // Carries PC and branch_id into ITTAGE at predict time.
  typedef struct packed {
    logic [VA_WIDTH-1:0]      pc;
    logic [FTQ_IDX_BITS-1:0]  branch_id;
  } ittage_pred_inp_t;

  // ITTAGE prediction metadata.
  // ittage_pred_strong: NOT WEAK, CTR != min or max. Used to gate
  // USE decrement on a longer non-hitting table.
  // ittage_hit: at least one IT1-IT5 entry matched.
  // When 0 consumer uses FTB target. ittage_pred_rdy_p2 still asserts.
  // altpred is the prediction from the next-longest hitting table.
  // USE_ALT_ON_NA: 4-bit counter gating alt use on null CTR.
  typedef struct packed {
    // Provider table index and selector
    logic [IT_MAX_IDX_WIDTH-1:0]   ittage_prm_idx;      // provider idx
    logic [IT_TBL_SEL_WIDTH-1:0]   ittage_prm_comp;     // provider tbl
    // Usefulness and confidence snapshot
    logic [IT_MAX_USE_WIDTH-1:0]   ittage_prm_useful;    // useful bits
    logic [IT_MAX_CTR_WIDTH-1:0]   ittage_prm_ctr;       // confidence ctr
    // Alternate provider table index and selector
    logic [IT_MAX_IDX_WIDTH-1:0]   ittage_alt_idx;      // alt provider idx
    logic [IT_TBL_SEL_WIDTH-1:0]   ittage_alt_comp;     // alt provider tbl
    // Alternate usefulness and confidence snapshot
    logic [IT_MAX_USE_WIDTH-1:0]   ittage_alt_useful;    // alt useful bits
    logic [IT_MAX_CTR_WIDTH-1:0]   ittage_alt_ctr;       // alt confidence ctr
    // Allocation target (new entry on miss)
    logic [IT_TBL_SEL_WIDTH-1:0]   ittage_alc_comp;      // alloc tbl
    logic [IT_MAX_IDX_WIDTH-1:0]   ittage_alc_idx;       // alloc idx
    logic [IT_MAX_TAG_WIDTH-1:0]   ittage_alc_tag;       // alloc tag
    // Predicted targets (upper 38b of Sv39 VA, bit 0 not stored)
    logic [IT_MAX_TGT_WIDTH-1:0]   ittage_prm_tgt;       // primary target
    logic [IT_MAX_TGT_WIDTH-1:0]   ittage_alt_tgt;       // alt target
    // Prediction flags
    logic                          ittage_hit;           // any tbl hit
    logic                          ittage_pred_strong;   // NOT WEAK
    logic                          ittage_use_alt_on_na; // USE_ALT_ON_NA
    logic                          ittage_using_primary; // primary supplied
    // FTQ entry index
    logic [FTQ_IDX_BITS-1:0]       branch_id;
  } ittage_pred_meta_t;

  // ITTAGE update input bundle.
  // Carries ittage_pred_meta_t captured at predict time plus
  // resolved target and mispredict flag from the execute stage.
  // resolved_target written to provider entry only on misprediction.
  typedef struct packed {
    ittage_pred_meta_t             ittage_pred_meta;
    logic [IT_MAX_TGT_WIDTH-1:0]   resolved_target;
    logic                          indir_mispredict;
  } ittage_upd_inp_t;

  // ----------------------------------------------------------------
  // Arbitration transaction register struct
  // ----------------------------------------------------------------
  // Travels with pipeline stage from p0/u0 to p1/u1.
  // trx_type encoding: 0 = PRED, 1 = UPD.
  typedef struct packed {
    logic                     trx_type;
    logic [TRX_SLOT_BITS-1:0] trx_slot;
  } bp_arb_trx_t;

  // ----------------------------------------------------------------
  // SC structs
  // ----------------------------------------------------------------
  // SC prediction metadata.
  // ----------------------------------------------------------------
  typedef struct packed {

    //SC supplied prediction
    logic sc_pred_tkn;     //This is SC+TAGE blocks final prediction
    logic sc_lcl_pred_tkn; //This is SC's prediction only, no override

    logic sc_tage_pred_tkn; //copy of tage_pred_meta.tage_pred_tkn

    //The SC over-rode the TAGE prediction
    logic sc_override;

    //ST0-ST3 table indexes captured during prediction used during update.
    //ST0 index is not hashed. This index can be used directly during update.
    //ST1-ST3 indexes are the hashed versions and can be used directly,
    //in update (i.e. no re-hash should be done).
    //ST4 index is derived from the BrIMLI register

    //SC tables index values used during prediction request, these
    //should be used directly in update (no additional hashing)
    logic [SC_NUM_TABLES-1:0][SC_MAX_IDX_WIDTH-1:0] sc_upd_idx;

    //SC tables ctr values at prediction request
    logic [SC_NUM_TABLES-1:0][SC_MAX_DATA_WIDTH-1:0] sc_upd_ctr;

    //The value of all entry outputs, includes ST0-ST4 and tage contribution
    logic signed   [SC_LSUM_BITS-1:0] sc_sum;
    logic unsigned [SC_LSUM_BITS-1:0] sc_abs_sum;

    //This range selector is calculated are prediction used during update
    bp_sc_chooser_e          sc_chooser;

    //FTQ entry index
    logic [FTQ_IDX_BITS-1:0]  branch_id;
    //logic [9:0]               branch_range;
    //logic [9:0]               captured_phr;

  } sc_pred_meta_t;

  // ----------------------------------------------------------------
  // SC update input.
  // ----------------------------------------------------------------
  typedef struct packed {

    //The meta data returned by SC during prediction
    sc_pred_meta_t  sc_pred_meta;

    //The execute resolved taken/not taken flag
    logic        resolved_taken;

    //Conditional branch mispredict
    logic        cond_mispredict;

    //FTB or BPU control logic sets this bit to indicate the branch being
    //predicted is a backwards branch (branch target < PC)
    logic        backwards_branch;
    logic [9:0]  branch_range; //bits 15:6 of the branch's PC

  } sc_upd_inp_t;

//  // ----------------------------------------------------------------
//  // Merged TAGE+SC prediction and update structs
//  // ----------------------------------------------------------------
//  typedef struct packed {
//    tage_pred_meta_t tage;
//    sc_pred_meta_t   sc;
//    logic            sc_valid;
//  } cond_pred_meta_t;
//
//  typedef struct packed {
//    tage_upd_inp_t  tage;
//    sc_upd_inp_t    sc;
//    logic           sc_valid;
//    logic           resolved_taken;
//    logic           cond_mispredict;
//  } cond_pred_upd_inp_t;

  // ----------------------------------------------------------------
  // Top-level structs
  // ----------------------------------------------------------------

  // bp_ftq_slot_t: one prediction slot of one fetch block.
  // The slots are the branch fields of one 32-byte FTB block, not
  // two PC ranges. See planning/arch/ftb_decisions.md 2.1, 2.3.
  // Carried as an array inside bp_ftq_entry_t.
  typedef struct packed {
    logic                      slot_valid; // slot carries a branch
    logic [VA_WIDTH-1:0]       target;     // predicted target
    bp_br_type_e               br_type;    // branch type
    logic                      taken;      // predicted taken/not-taken
    logic [FTB_BR_POS_BITS-1:0] pos;       // in-block position 0..15
    bp_pred_src_e              pred_src;   // predictor that won
    logic [FTQ_CONF_BITS-1:0]  confidence; // saturating confidence (TBD)
  } bp_ftq_slot_t;

  // bp_ftq_entry_t: fast-path FTQ entry.
  // Stored in a fast SRAM read every cycle by the front-end.
  // One entry holds one fetch block and all NUM_PRED_SLOTS
  // predictions for it.
  // The RAS snapshot is stored here for O(1) redirect recovery.
  // ghist_ptr and phist_ptr are this entry's history checkpoint.
  //
  // pft_addr is the block fall-through: the address fetched after
  // this block when no slot in it is taken. It is the third arm of
  // the successor selection of fe_decisions.md 2.4, written at p1
  // from bpu_pred_pft_p1 (TD#108). It is stored rather than re-
  // derived because the selection is re-evaluated whenever a
  // redirect rewrites a slot, so the not-taken term is needed after
  // p1 and cannot be recovered from the rest of the entry.
  typedef struct packed {
    logic [VA_WIDTH-1:0]       pc;         // fetch block start PC
    logic [VA_WIDTH-1:0]       pft_addr;   // block fall-through addr
    logic [FTQ_IDX_BITS-1:0]   branch_id;  // FTQ entry index
    bp_ras_snapshot_t          ras;        // RAS pointer snapshot
    logic [GHIST_PTR_BITS-1:0] ghist_ptr;  // GHR circular buf pointer
    logic [PHIST_PTR_BITS-1:0] phist_ptr;  // PHR circular buf pointer
    logic                      valid;
    // Per-slot prediction fields. Packed-struct dimension descends.
    bp_ftq_slot_t [NUM_PRED_SLOTS-1:0] slot;
  } bp_ftq_entry_t;

  // ftb_pred_meta_t: FTB state captured at the prediction read and
  // returned on the update port. The FTB does not re-look-up the tag
  // at update; the hit result and the write way are carried
  // (IC-FTB-10). Scalar within the entry: the FTB indexes one entry
  // per lookup and both slots come from it.
  typedef struct packed {
    logic                       hit;     // tag hit at predict
    logic [FTB_WAY_BITS-1:0]    way;     // hit way, or PLRU victim
    logic [FTB_BR_POS_BITS-1:0] jmp_pos; // jump in-block position
  } ftb_pred_meta_t;

  // bp_ftq_meta_t: slow-path FTQ metadata.
  // Stored in a separate wide SRAM. Read only on post-execute update.
  // Carried per prediction slot. The array
  //   bp_ftq_meta_t [NUM_PRED_SLOTS-1:0]
  // is declared at instantiation, not inside this struct.
  // Fields are logically union-overloaded by branch type; full
  // overload scheme is TBD at implementation.
  typedef struct packed {
    tage_pred_meta_t   tage;   // TAGE predictor state
    sc_pred_meta_t     sc;     // SC predictor state
    lp_pred_t          lp;     // loop predictor state
    ittage_pred_meta_t ittage; // ITTAGE predictor state
    ftb_pred_meta_t    ftb;    // FTB carried hit / way / jmp pos
  } bp_ftq_meta_t;

  // ----------------------------------------------------------------
  // Update channel struct
  // ----------------------------------------------------------------

  // bp_update_t: post-execute update channel.
  // Trigger: post-execute resolution (does not wait for retire).
  // One channel per prediction slot. The array
  //   bp_update_t [NUM_PRED_SLOTS-1:0]
  // is declared at instantiation, not inside this struct.
  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0] branch_id;     // FTQ entry index
    logic [VA_WIDTH-1:0]     pc;            // fetch PC of branch
    logic                    actual_taken;  // resolved direction
    logic [VA_WIDTH-1:0]     actual_target; // resolved target
    bp_br_type_e             br_type;       // branch type
    logic                    mispredicted;  // was a misprediction
    logic                    valid;
  } bp_update_t;

  // ----------------------------------------------------------------
  // Redirect struct
  // ----------------------------------------------------------------

  // bp_redirect_t: pipeline redirect signal.
  // Per-slot payload. The array
  //   bp_redirect_t [0:NUM_PRED_SLOTS-1]
  // is declared at the port, with a scalar FTQ entry index
  // alongside it: both slots occupy one FTQ entry.
  // Used for both p2_redirect and p3_redirect outputs.
  // p2: fires when FTB/TAGE/ITTAGE/RAS disagrees with the entry.
  // p3: fires when SC overrides TAGE direction from p2.
  // ftq_idx;  removed from struct since it is shared across slots
  typedef struct packed {
    logic [VA_WIDTH-1:0]      target_pc; // redirect target address
    //logic [FTQ_IDX_BITS-1:0]  ftq_idx;   // FTQ entry being squashed
    logic                     valid;
  } bp_redirect_t;

  // ----------------------------------------------------------------
  // FTQ boundary structs
  // ----------------------------------------------------------------

  // ftq_resolve_t: one backend resolution channel into the FTQ.
  // ftq_backend_interfaces.md 4. Carried as
  //   ftq_resolve_t [0:NUM_RESOLVE_PORTS-1]
  // at the port, ascending, per the port-dimension convention.
  //
  // THE BACKEND NAMES A POSITION, NOT A SLOT. Prediction slots are
  // the two branch fields of one FTB block (FE-10) and nothing
  // outside the BPU and the FTQ has reason to know which field a
  // branch landed in. The IFU tags each instruction from its own
  // predecode, and predecode yields a position; the FTQ maps
  // position to slot by matching pos against the entry's slot pos
  // fields. bp_update_t cannot acquire a position field without
  // breaking FE-10, which is why this type exists alongside it.
  typedef struct packed {
    logic [FTQ_IDX_BITS-1:0]    ftq_idx;    // entry that fetched it
    logic [FTB_BR_POS_BITS-1:0] pos;        // in-block position
    logic                       taken;      // resolved direction
    logic [VA_WIDTH-1:0]        target;     // resolved target
    bp_br_type_e                br_type;    // resolved type
    logic                       mispredict;
  } ftq_resolve_t;

  // ftq_pd_info_t: one predecode slot of the IFU writeback.
  // ftq_ifu_interfaces.md 6. Carried as
  //   ftq_pd_info_t [FTQ_PD_WIDTH-1:0]
  // one per 2-byte position in the 32-byte prediction block.
  //
  // br_type here is the PREDECODE classification, two bits, and is
  // NOT bp_br_type_e. Predecode knows only the encoding it decoded;
  // the FTQ maps this pair plus is_call and is_ret onto
  // bp_br_type_e when it rewrites the slot (ftq_ifu_interfaces.md
  // 7 W1).
  typedef struct packed {
    logic       valid;   // slot holds an instruction start
    logic       is_rvc;  // 16-bit encoding
    logic [1:0] br_type; // 00 not CFI, 01 branch, 10 jal, 11 jalr
    logic       is_call;
    logic       is_ret;
  } ftq_pd_info_t;

  // ----------------------------------------------------------------
  // uBTB structs
  // ----------------------------------------------------------------
  // The uBTB entry mirrors the FTB entry (ftb_decisions.md 4): two
  // conditional fields, one jump field, and a partial fallthrough,
  // describing one UBTB_BLOCK_BYTES block. One lookup supplies both
  // prediction slots.
  //
  // Targets are stored as displacements from block start with a
  // fit/overflow/underflow status (ftb_decisions.md 4.2). The
  // encoding is lossless when the branch is in reach.

  // One conditional branch field. 1+3+13+2+3 = 22 bits.
  typedef struct packed {
    logic                          valid;  // field occupied
    logic [UBTB_BR_POS_BITS-1:0]   pos;    // in-block position 0..15
    logic [UBTB_BR_TGT_BITS-1:0]   tgt;    // target displacement
    logic [TAR_STAT_BITS-1:0]      stat;   // fit / ovf / udf
    logic [UBTB_CONF_WIDTH-1:0]    conf;   // bimodal direction; MSB
                                           // is the direction
  } ubtb_cond_t;

  // The block-terminating jump field. 1+3+21+2+3 = 30 bits.
  typedef struct packed {
    logic                          valid;    // field occupied
    logic [UBTB_BR_POS_BITS-1:0]   pos;      // in-block position
    logic [UBTB_JMP_TGT_BITS-1:0]  tgt;      // jump displacement
    logic [TAR_STAT_BITS-1:0]      stat;     // fit / ovf / udf
    logic                          is_call;
    logic                          is_ret;
    logic                          is_jalr;
  } ubtb_jmp_t;

  // One uBTB storage entry (one way of one set).
  // 1 + 20 + 23 + 23 + 31 + 5 + 1 = 104 bits.
  // The tag is the UBTB_TAG_BITS VA bits immediately above the
  // block-granularity index, not a retired-instruction-granularity
  // field: index = pc[10:5], tag = pc[30:11] at VA_WIDTH 40 with a
  // 32-byte block. See bp_defines_pkg.sv, UBTB_TAG_BITS.
  typedef struct packed {
    logic                          valid;  // entry valid
    logic [UBTB_TAG_BITS-1:0]      tag;    // pc[30:11]
    ubtb_cond_t                    br0;    // conditional field 0
    ubtb_cond_t                    br1;    // conditional field 1
    ubtb_jmp_t                     jmp;    // terminal jump field
    logic [UBTB_PFTADDR_BITS-1:0]  pft;    // partial fallthrough
    logic                          carry;  // fallthrough crosses the
                                           // block boundary
  } ubtb_entry_t;

  // Prediction output for one prediction slot. Slot 0 is built from
  // the entry br0 field, slot 1 from br1. A slot carrying the
  // block-terminating jump reports that jump type and target.
  // Targets are reconstructed to full width by ubtb.sv.
  typedef struct packed {
    logic                          valid;    // slot carries a branch
    logic [VA_WIDTH-1:0]           target;   // reconstructed target
    bp_br_type_e                   br_type;  // branch type
    logic                          br_taken; // direction, COND only
    logic [UBTB_BR_POS_BITS-1:0]   pos;      // in-block position
    logic [UBTB_CONF_WIDTH-1:0]    conf;     // bimodal direction ctr
    logic                          carry;    // entry fall-through
                                             // carry, copied from the
                                             // stored entry carry
                                             // bit: the block end
                                             // crosses the block
                                             // boundary. Entry
                                             // scoped, not a
                                             // property of this
                                             // slot's target.
  } ubtb_pred_t;

  // Entry-scoped prediction sidebands, one set per lookup. Both slots
  // come from one entry, so the hit and the block end are reported
  // once rather than per slot.
  typedef struct packed {
    logic                          hit;      // entry valid and tag
                                             // matched
    logic [VA_WIDTH-1:0]           pft_addr; // reconstructed
                                             // fallthrough
  } ubtb_blk_t;

  // Update bundle for one prediction slot. Driven post-execute by the
  // resolution path. The field set mirrors the FTB update port, so
  // one set of resolved facts forms both updates.
  typedef struct packed {
    logic                          valid;      // update active
    logic [VA_WIDTH-1:0]           pc;         // block start PC
    logic                          is_br;      // conditional resolve
    logic                          br_idx;     // which conditional
                                               // field, 0 or 1
    logic                          br_taken;   // resolved direction
    logic [VA_WIDTH-1:0]           target;     // resolved taken
                                               // target, full width
    logic [UBTB_BR_POS_BITS-1:0]   pos;        // in-block position
    logic                          is_jmp;     // jump resolve
    logic [VA_WIDTH-1:0]           jmp_target; // resolved jump target
    logic                          is_call;
    logic                          is_ret;
    logic                          is_jalr;
    logic [VA_WIDTH-1:0]           pft_addr;   // resolved block end,
                                               // full width
  } ubtb_upd_t;

  // ----------------------------------------------------------------
  // Loop predictor structs
  // ----------------------------------------------------------------

  // lp_entry_t: one storage entry (one way of one set).
  // | 67    | 66:53 | 52:39 | 38:25    | 24:11    | 10:3 | 2:1 | 0 |
  // | curs_v| curs  | tag   | past_itr | curr_itr | age  | cnf | v |
  // | 1     | 13:0  | 13:0  | 13:0     | 13:0     | 7:0  | 1:0 | 1 |
  typedef struct packed {
    logic                   curs_v;   // cursor valid
    logic [LP_ITR_BITS-1:0] curs;     // speculative progress cursor
    logic [LP_TAG_BITS-1:0] tag;      // tag
    logic [LP_ITR_BITS-1:0] past_itr; // past iteration count
    logic [LP_ITR_BITS-1:0] curr_itr; // current iteration count
    logic [LP_AGE_BITS-1:0] age;      // age/replacement counter
    logic [LP_CNF_BITS-1:0] cnf;      // confidence counter
    logic                   v;        // valid
  } lp_entry_t;

  // lp_pred_t is declared in the Sub-structs section above, ahead of
  // bp_ftq_meta_t, which embeds it as its lp member (TD#106).

  // lp_upd_t: update bundle for the loop predictor.
  // All lp_pred_t fields repeated flat (no sub-struct embedding)
  // plus pc, target, and actual_taken from the execute stage.
  // target enables backward branch filter at module level
  // (alloc only when upd.target < upd.pc).
  typedef struct packed {
    logic [VA_WIDTH-1:0]     pc;              // fetch PC of branch
    logic [VA_WIDTH-1:0]     target;          // resolved target address
    logic                    actual_taken;    // resolved direction
    logic [LP_IDX_BITS-1:0]  lp_idx;          // set index at predict time
    logic [LP_TAG_BITS-1:0]  lp_tag;          // tag at predict time
    logic [LP_WAY_BITS-1:0]  lp_way;          // way that hit
    logic                    lp_hit;          // tag match at predict time
    logic                    lp_pred_is_loop; // loop predictor trusted
    logic                    lp_pred_taken;   // direction used
    logic [LP_AGE_BITS-1:0]  lp_age;          // age counter snapshot
    logic [LP_CNF_BITS-1:0]  lp_conf;         // confidence counter snapshot
    logic [LP_ITR_BITS-1:0]  lp_past_itr;     // past iteration count
    logic [LP_ITR_BITS-1:0]  lp_curr_itr;     // current iteration count
    logic [LP_ITR_BITS-1:0]  lp_curs;         // speculative cursor
    logic                    lp_curs_v;       // cursor valid
    logic [LP_WAY_BITS-1:0]  lp_victim;       // allocation target way
  } lp_upd_t;

  // ------------------------------------------------------------------
  // ftb_upd_t: the FTB update payload as one struct (BP-100).
  //
  // The cluster boundary declares these same 14 fields FLAT, with no
  // slot dimension and no ready (ftq_bpu_interfaces.md 8). The FTQ
  // has two update channels and the FTB has one port, so
  // ftq_ftb_sched carries two of these and flattens the winner back
  // onto the cluster's flat group. The flat ports are NOT replaced:
  // this struct exists so the scheduler can move a whole update as
  // one object, which the flat form cannot express.
  //
  // ftb_upd_valid_u0 is NOT a member. Validity qualifies a channel,
  // not a payload, and the scheduler carries it per channel.
  typedef struct packed {
    logic [VA_WIDTH-1:0]        pc;         // fetch PC of the block
    logic                       hit;        // FTB hit at predict time
    logic [FTB_WAY_BITS-1:0]    way;        // way that hit, or victim
    logic                       is_br;      // carries a conditional
    logic                       br_idx;     // which conditional field
    logic                       taken;      // resolved direction
    logic [VA_WIDTH-1:0]        target;     // resolved branch target
    logic [FTB_BR_POS_BITS-1:0] pos;        // in-block position
    logic                       is_jmp;     // carries the jump field
    logic [VA_WIDTH-1:0]        jmp_target; // resolved jump target
    logic                       is_call;    // jump is a call
    logic                       is_ret;     // jump is a return
    logic                       is_jalr;    // jump is indirect
    logic [VA_WIDTH-1:0]        pft_addr;   // block fall-through
  } ftb_upd_t;

endpackage : bp_structs_pkg

`endif // BP_STRUCTS_PKG_SV

