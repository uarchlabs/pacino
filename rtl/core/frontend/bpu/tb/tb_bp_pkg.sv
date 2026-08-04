// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// FILE:    tb_bp_pkg.sv
// DATE:    2026-05-21
// CONTACT: Jeff Nye
// -------------------------------------------------------------------
// Testbench: bp_pkg type and parameter checks (BP-001).
// No clock required -- purely combinational checks.
// Self-checking: $fatal on any failure.
// ===================================================================

module tb;
  import bp_defines_pkg::*;
  import bp_structs_pkg::*;

  // Declare instances of all top-level struct types.
  // Verifies that all struct and enum types elaborate without error.
  bp_ftq_entry_t  entry_a;
  bp_ftq_entry_t  entry_b;
  bp_ftq_meta_t   meta;
  bp_update_t     upd;
  bp_redirect_t   redir;

  // Expected struct widths, derived from the package field lists.
  // A field added to or removed from either struct changes these and
  // the width checks below catch it.
  localparam int SLOT_BITS  = 1 + VA_WIDTH + $bits(bp_br_type_e) +
                              1 + $bits(bp_pred_src_e) +
                              FTQ_CONF_BITS;
  localparam int ENTRY_BITS = VA_WIDTH + FTQ_IDX_BITS +
                              (3 * RAS_PTR_BITS) + GHIST_PTR_BITS +
                              PHIST_PTR_BITS + 1 +
                              (NUM_PRED_SLOTS * SLOT_BITS);

  // Slot 1 stimulus. Chosen distinct from the slot 0 pattern so a
  // cross-slot aliasing defect cannot pass unnoticed.
  localparam logic [VA_WIDTH-1:0]      SLOT1_TGT =
                                         VA_WIDTH'('h12_3456_789A);
  localparam logic [FTQ_CONF_BITS-1:0] SLOT1_CONF =
                                         FTQ_CONF_BITS'('h5);

  // Second slot 0 pattern, written by the slot independence check.
  localparam logic [VA_WIDTH-1:0]      SLOT0_TGT2 =
                                         VA_WIDTH'('hA5_A5A5_A5A5);

  int pass_count;

  initial begin
    pass_count = 0;

    // --------------------------------------------------------------
    // Width checks: verify key field bit widths at runtime.
    // $bits() is evaluated from the type; variable need not be driven.
    // --------------------------------------------------------------

    // ghist_ptr must be GHIST_PTR_BITS wide
    if ($bits(entry_a.ghist_ptr) !== GHIST_PTR_BITS) begin
      $fatal(1, "FAIL ghist_ptr: got %0d, want %0d",
             $bits(entry_a.ghist_ptr), GHIST_PTR_BITS);
    end
    pass_count++;

    // phist_ptr must be PHIST_PTR_BITS wide
    if ($bits(entry_a.phist_ptr) !== PHIST_PTR_BITS) begin
      $fatal(1, "FAIL phist_ptr: got %0d, want %0d",
             $bits(entry_a.phist_ptr), PHIST_PTR_BITS);
    end
    pass_count++;

    // pc must be VA_WIDTH bits wide
    if ($bits(entry_a.pc) !== VA_WIDTH) begin
      $fatal(1, "FAIL entry_a.pc: got %0d, want %0d",
             $bits(entry_a.pc), VA_WIDTH);
    end
    pass_count++;

    // target must be VA_WIDTH bits wide
    if ($bits(entry_a.slot[0].target) !== VA_WIDTH) begin
      $fatal(1, "FAIL entry_a.slot[0].target: got %0d, want %0d",
             $bits(entry_a.slot[0].target), VA_WIDTH);
    end
    pass_count++;

    // branch_id must be FTQ_IDX_BITS wide
    if ($bits(entry_a.branch_id) !== FTQ_IDX_BITS) begin
      $fatal(1, "FAIL branch_id: got %0d, want %0d",
             $bits(entry_a.branch_id), FTQ_IDX_BITS);
    end
    pass_count++;

    // RAS snapshot: tosr, tosw, bos must each be RAS_PTR_BITS wide
    if ($bits(entry_a.ras.tosr) !== RAS_PTR_BITS) begin
      $fatal(1, "FAIL ras.tosr: got %0d, want %0d",
             $bits(entry_a.ras.tosr), RAS_PTR_BITS);
    end
    pass_count++;

    if ($bits(entry_a.ras.tosw) !== RAS_PTR_BITS) begin
      $fatal(1, "FAIL ras.tosw: got %0d, want %0d",
             $bits(entry_a.ras.tosw), RAS_PTR_BITS);
    end
    pass_count++;

    if ($bits(entry_a.ras.bos) !== RAS_PTR_BITS) begin
      $fatal(1, "FAIL ras.bos: got %0d, want %0d",
             $bits(entry_a.ras.bos), RAS_PTR_BITS);
    end
    pass_count++;

    // lp_tag must be LP_TAG_BITS wide
    if ($bits(meta.lp.lp_tag) !== LP_TAG_BITS) begin
      $fatal(1, "FAIL lp_tag: got %0d, want %0d",
             $bits(meta.lp.lp_tag), LP_TAG_BITS);
    end
    pass_count++;

    // lp_pst_itr must be LP_ITR_BITS wide
    if ($bits(meta.lp.lp_pst_itr) !== LP_ITR_BITS) begin
      $fatal(1, "FAIL lp_pst_itr: got %0d, want %0d",
             $bits(meta.lp.lp_pst_itr), LP_ITR_BITS);
    end
    pass_count++;

    // sc_upd_idx[0] must be SC_MAX_IDX_WIDTH wide
    if ($bits(meta.sc.sc_upd_idx[0]) !== SC_MAX_IDX_WIDTH) begin
      $fatal(1, "FAIL sc_upd_idx[0]: got %0d, want %0d",
             $bits(meta.sc.sc_upd_idx[0]), SC_MAX_IDX_WIDTH);
    end
    pass_count++;

    // update channel: branch_id must be FTQ_IDX_BITS wide
    if ($bits(upd.branch_id) !== FTQ_IDX_BITS) begin
      $fatal(1, "FAIL upd.branch_id: got %0d, want %0d",
             $bits(upd.branch_id), FTQ_IDX_BITS);
    end
    pass_count++;

    // redirect struct: target_pc must be VA_WIDTH wide
    if ($bits(redir.target_pc) !== VA_WIDTH) begin
      $fatal(1, "FAIL redir.target_pc: got %0d, want %0d",
             $bits(redir.target_pc), VA_WIDTH);
    end
    pass_count++;

    // bp_ftq_slot_t must be SLOT_BITS wide
    if ($bits(entry_a.slot[0]) !== SLOT_BITS) begin
      $fatal(1, "FAIL bp_ftq_slot_t: got %0d, want %0d",
             $bits(entry_a.slot[0]), SLOT_BITS);
    end
    pass_count++;

    // bp_ftq_entry_t must be ENTRY_BITS wide
    if ($bits(entry_a) !== ENTRY_BITS) begin
      $fatal(1, "FAIL bp_ftq_entry_t: got %0d, want %0d",
             $bits(entry_a), ENTRY_BITS);
    end
    pass_count++;

    // --------------------------------------------------------------
    // Enum distinctness: bp_br_type_e (7 values, must all differ)
    // --------------------------------------------------------------
    if (COND == DIRECT_CALL || COND == INDIRECT_CALL ||
        COND == RETURN || COND == INDIRECT_NONRET ||
        COND == DIRECT_UNC || COND == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: COND collides");
    end
    if (DIRECT_CALL == INDIRECT_CALL || DIRECT_CALL == RETURN ||
        DIRECT_CALL == INDIRECT_NONRET ||
        DIRECT_CALL == DIRECT_UNC || DIRECT_CALL == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: DIRECT_CALL collides");
    end
    if (INDIRECT_CALL == RETURN || INDIRECT_CALL == INDIRECT_NONRET ||
        INDIRECT_CALL == DIRECT_UNC ||
        INDIRECT_CALL == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: INDIRECT_CALL collides");
    end
    if (RETURN == INDIRECT_NONRET || RETURN == DIRECT_UNC ||
        RETURN == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: RETURN collides");
    end
    if (INDIRECT_NONRET == DIRECT_UNC ||
        INDIRECT_NONRET == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: INDIRECT_NONRET collides");
    end
    if (DIRECT_UNC == NO_BRANCH) begin
      $fatal(1, "FAIL bp_br_type_e: DIRECT_UNC == NO_BRANCH");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Enum distinctness: bp_pred_src_e (8 values, must all differ)
    // --------------------------------------------------------------
    if (PRED_UBTB == PRED_LOOP || PRED_UBTB == PRED_FTB ||
        PRED_UBTB == PRED_TAGE || PRED_UBTB == PRED_SC ||
        PRED_UBTB == PRED_ITTAGE || PRED_UBTB == PRED_RAS ||
        PRED_UBTB == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_UBTB collides");
    end
    if (PRED_LOOP == PRED_FTB || PRED_LOOP == PRED_TAGE ||
        PRED_LOOP == PRED_SC || PRED_LOOP == PRED_ITTAGE ||
        PRED_LOOP == PRED_RAS || PRED_LOOP == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_LOOP collides");
    end
    if (PRED_FTB == PRED_TAGE || PRED_FTB == PRED_SC ||
        PRED_FTB == PRED_ITTAGE || PRED_FTB == PRED_RAS ||
        PRED_FTB == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_FTB collides");
    end
    if (PRED_TAGE == PRED_SC || PRED_TAGE == PRED_ITTAGE ||
        PRED_TAGE == PRED_RAS || PRED_TAGE == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_TAGE collides");
    end
    if (PRED_SC == PRED_ITTAGE || PRED_SC == PRED_RAS ||
        PRED_SC == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_SC collides");
    end
    if (PRED_ITTAGE == PRED_RAS || PRED_ITTAGE == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_ITTAGE collides");
    end
    if (PRED_RAS == PRED_NONE) begin
      $fatal(1, "FAIL bp_pred_src_e: PRED_RAS == PRED_NONE");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Struct packing check: assign all fields of entry_a, copy to
    // entry_b, verify equality with ===.
    // --------------------------------------------------------------
    entry_a.pc           = {VA_WIDTH{1'b0}};
    entry_a.branch_id    = {FTQ_IDX_BITS{1'b1}};
    entry_a.ras.tosr     = RAS_PTR_BITS'('h5);
    entry_a.ras.tosw     = RAS_PTR_BITS'('hA);
    entry_a.ras.bos      = RAS_PTR_BITS'('h1);
    entry_a.ghist_ptr    = {GHIST_PTR_BITS{1'b1}};
    entry_a.phist_ptr    = {PHIST_PTR_BITS{1'b1}};
    entry_a.valid        = 1'b1;

    // Slot 0 carries the values the scalar fields carried before the
    // per-slot split, so the expected results above are preserved.
    entry_a.slot[0].slot_valid = 1'b1;
    entry_a.slot[0].target     = {VA_WIDTH{1'b1}};
    entry_a.slot[0].br_type    = COND;
    entry_a.slot[0].taken      = 1'b1;
    entry_a.slot[0].pred_src   = PRED_TAGE;
    entry_a.slot[0].confidence = {FTQ_CONF_BITS{1'b1}};

    // Slot 1 driven with a distinct value in every field.
    entry_a.slot[1].slot_valid = 1'b1;
    entry_a.slot[1].target     = SLOT1_TGT;
    entry_a.slot[1].br_type    = RETURN;
    entry_a.slot[1].taken      = 1'b0;
    entry_a.slot[1].pred_src   = PRED_RAS;
    entry_a.slot[1].confidence = SLOT1_CONF;

    entry_b = entry_a;

    if (entry_a !== entry_b) begin
      $fatal(1, "FAIL struct packing: entry_a !== entry_b after copy");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Slot array read-back: each slot returns the values written to
    // it, and no slot returns its neighbour's values.
    // --------------------------------------------------------------
    if (entry_a.slot[0].slot_valid !== 1'b1 ||
        entry_a.slot[0].target     !== {VA_WIDTH{1'b1}} ||
        entry_a.slot[0].br_type    !== COND ||
        entry_a.slot[0].taken      !== 1'b1 ||
        entry_a.slot[0].pred_src   !== PRED_TAGE ||
        entry_a.slot[0].confidence !== {FTQ_CONF_BITS{1'b1}}) begin
      $fatal(1, "FAIL slot[0] read-back: written values not returned");
    end
    pass_count++;

    if (entry_a.slot[1].slot_valid !== 1'b1 ||
        entry_a.slot[1].target     !== SLOT1_TGT ||
        entry_a.slot[1].br_type    !== RETURN ||
        entry_a.slot[1].taken      !== 1'b0 ||
        entry_a.slot[1].pred_src   !== PRED_RAS ||
        entry_a.slot[1].confidence !== SLOT1_CONF) begin
      $fatal(1, "FAIL slot[1] read-back: written values not returned");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Slot independence: rewriting one slot leaves the other slot and
    // the block-scalar fields untouched. entry_b holds the pre-
    // rewrite image and supplies the expected values.
    // --------------------------------------------------------------
    entry_a.slot[0].slot_valid = 1'b0;
    entry_a.slot[0].target     = SLOT0_TGT2;
    entry_a.slot[0].br_type    = DIRECT_UNC;
    entry_a.slot[0].taken      = 1'b0;
    entry_a.slot[0].pred_src   = PRED_FTB;
    entry_a.slot[0].confidence = {FTQ_CONF_BITS{1'b0}};

    if (entry_a.slot[1] !== entry_b.slot[1]) begin
      $fatal(1, "FAIL independence: slot[0] write disturbed slot[1]");
    end
    pass_count++;

    entry_a.slot[1].slot_valid = 1'b0;
    entry_a.slot[1].target     = {VA_WIDTH{1'b0}};
    entry_a.slot[1].br_type    = NO_BRANCH;
    entry_a.slot[1].taken      = 1'b0;
    entry_a.slot[1].pred_src   = PRED_NONE;
    entry_a.slot[1].confidence = {FTQ_CONF_BITS{1'b0}};

    if (entry_a.slot[0].slot_valid !== 1'b0 ||
        entry_a.slot[0].target     !== SLOT0_TGT2 ||
        entry_a.slot[0].br_type    !== DIRECT_UNC ||
        entry_a.slot[0].taken      !== 1'b0 ||
        entry_a.slot[0].pred_src   !== PRED_FTB ||
        entry_a.slot[0].confidence !== {FTQ_CONF_BITS{1'b0}}) begin
      $fatal(1, "FAIL independence: slot[1] write disturbed slot[0]");
    end
    pass_count++;

    if (entry_a.pc        !== entry_b.pc        ||
        entry_a.branch_id !== entry_b.branch_id ||
        entry_a.ras       !== entry_b.ras       ||
        entry_a.ghist_ptr !== entry_b.ghist_ptr ||
        entry_a.phist_ptr !== entry_b.phist_ptr ||
        entry_a.valid     !== entry_b.valid) begin
      $fatal(1, "FAIL independence: slot writes disturbed scalars");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Summary
    // --------------------------------------------------------------
    $display("BP-001: %0d checks passed", pass_count);
    $finish;
  end

endmodule : tb
