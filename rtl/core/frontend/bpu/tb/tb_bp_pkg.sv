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
    if ($bits(entry_a.target) !== VA_WIDTH) begin
      $fatal(1, "FAIL entry_a.target: got %0d, want %0d",
             $bits(entry_a.target), VA_WIDTH);
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
    entry_a.target       = {VA_WIDTH{1'b1}};
    entry_a.br_type      = COND;
    entry_a.taken        = 1'b1;
    entry_a.pred_src     = PRED_TAGE;
    entry_a.confidence   = {FTQ_CONF_BITS{1'b1}};
    entry_a.branch_id    = {FTQ_IDX_BITS{1'b1}};
    entry_a.ras.tosr     = 6'h15;
    entry_a.ras.tosw     = 6'h2a;
    entry_a.ras.bos      = 6'h01;
    entry_a.ghist_ptr    = {GHIST_PTR_BITS{1'b1}};
    entry_a.phist_ptr    = {PHIST_PTR_BITS{1'b1}};
    entry_a.valid        = 1'b1;

    entry_b = entry_a;

    if (entry_a !== entry_b) begin
      $fatal(1, "FAIL struct packing: entry_a !== entry_b after copy");
    end
    pass_count++;

    // --------------------------------------------------------------
    // Summary
    // --------------------------------------------------------------
    $display("BP-001: %0d checks passed", pass_count);
    $finish;
  end

endmodule : tb
