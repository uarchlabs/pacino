# Session Handoff 042
Written by Claude.ai at end of session-041.
Date: 2026-05-18

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-041 completed ittage.sv in six prompts
(BP-037, BP-037a, BP-037b, BP-038, BP-038a) plus
associated fix passes. ittage.sv is complete with
full arbitration layer. lint clean.

---

## What This Session Accomplished

### BP-037 (complete)

ittage.sv structural wrapper. Instantiated ittage_cntrl
and five ittage_table instances (IT1-IT5) with correct
per-table parameter assignments. Single shared sram_init.
fast_init support via +ITTAGE_FAST_INIT plusarg.
No arbitration logic.

Key decisions:
  - One sram_init instance at ittage.sv top level.
    ADDR_BITS=IT_MAX_IDX_WIDTH,
    DATA_WIDTH=IT_MAX_ALLOC_DATA_WIDTH.
  - alc_wd_u0 sliced per table: IT1-IT4 receive lower
    bits only, IT5 receives full 57b width.
  - idx_hash_p0 zero-extended from per-table TH_IDX
    width to IT_MAX_IDX_WIDTH for ittage_cntrl input.
  - Named generate blocks: gen_ittage_tables (t=0..4,
    t=0 skipped via gen_active), gen_slot_signals.

### BP-037a (complete)

Fixed sram_init instantiation. BP-037 incorrectly
instantiated one sram_init per ittage_table (five
total). Corrected to one shared instance at module
top level.

### BP-037b (complete)

Restored fast_init tbl_ri_* strapping to zero.
BP-037a removed the fast_init mux when restructuring
to single sram_init. Restored:
  - fast_init active: tbl_ri_wr, tbl_ri_wa, tbl_ri_wd
    driven to zero on all five ittage_table instances.
  - fast_init inactive: tbl_ri_* driven from sram_init
    outputs with per-table width slicing.

Note: tbl_ri_cs does not exist as a port on
ittage_table. tbl_ri_active is the mux select for
the RAM control path. fast_init does not gate
tbl_ri_active -- confirmed harmless by Jeff.

### BP-038 (complete)

Arbitration layer added to ittage.sv. PQ, UQ, credit
arbiter, competing stage mux, bp_arb_trx_t register,
and prediction response buffer. Follows tage.sv
pattern with ITTAGE_ prefixed parameters.

Key decisions:
  - UQ entry type: ittage_upd_inp_t directly.
    No merged struct. No sc field.
  - RB entry type: ittage_pred_meta_t directly.
  - consumer_ready = 1'b1 internally. Not a port.
    RB always in bypass mode. Correct for ITTAGE
    with no downstream SC consumer.
  - trx_type_comb = arb_grant_upd (combinational).
  - pq_not_full and upd_rdy added as output ports.
    Not yet in ittage_interfaces.md (TD #47).
  - Parameter prefix error in prompt (ITAGE_ vs
    ITTAGE_). bp_defines_pkg.sv uses ITTAGE_.
    Claude Code used correct package names.

### BP-038a (complete)

Added trx_type input port to ittage_cntrl.sv.
Resolves tech debt #46. Write enables gated in
four always_comb blocks (g_ctr_upd, g_use_upd,
g_tgt_upd, g_alc_upd). Prediction read result
routing gated: ittage_pred_rdy_p2 = trx_type ?
'0 : rdy_p2_r. Connected to trx_type_comb in
ittage.sv. Lint clean first attempt.

Note: UAON always_ff block not gated with trx_type.
Consistent with registered update path pattern.
Verify at tb_ittage concurrent pred+upd tests.

---

## Methodology Updates This Session

  1. Fix prompts must state required end state
     explicitly, not delta from prior session.
     Claude Code has no memory. "Restore X"
     is not actionable. Describe the required
     behavior in full.

  2. Fix prompts must explicitly state what must
     not change, with the exact working behavior
     reproduced in Constraints -- not referenced,
     not paraphrased. Exact behavior stated.

  3. sram_init count must be stated explicitly
     in any prompt that instantiates it. Never
     defer to planning documents for instance
     count.

---

## Open Technical Debt

  - TD #43: ittage_pred_strong definition in
    ittage_cntrl_decisions.md incorrect. Needs
    update to CTR > 0 (not NULL). Deferred.
  - TD #44: ittage_cntrl_decisions.md decoration
    flags section needs correction when TD #43
    is implemented.
  - TD #45: TAGE T0 index handling needs revisit.
  - TD #47: ittage_interfaces.md missing pq_not_full
    and upd_rdy ports. Added to ittage.sv in BP-038.
    Assess for closure next session.
  - TD #48: ittage.sv RB bypass behavior with
    consumer_ready=1'b1. Verify against bp_cluster
    backpressure expectations at cluster integration.
    Assess for closure next session.
  - alc_index_u0 over-design: currently =
    upd_index_u0. Correct value is alc_idx from
    meta. Deferred until performance analysis.
  - CTR width: IT_TBL_CTR currently 3b. 2b may be
    sufficient. Multi-file change deferred.

---

## Next Session (042)

ittage.sv is complete with arbitration. Next step
is tb_ittage.sv (BP-039).

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-042.md (this file)
  CLAUDE.md

### Planned work

**Step 1 -- Verify planning documents complete**
  Assess TD #47 and TD #48 for closure:
    TD #47: add pq_not_full and upd_rdy to
      ittage_interfaces.md.
    TD #48: confirm RB bypass behavior is correct
      for ITTAGE with no SC consumer.
  If either requires a planning document update,
  make that update before proceeding to BP-039.

**Step 2 -- Verify ittage.sv against documents**
  Cross-check ittage.sv port list against
  ittage_interfaces.md. Verify all ports present
  and correctly typed.
  Review arbitration implementation against
  bp_arb_spec.md. Verify seven-rule credit
  arbiter, PQ/UQ bypass conditions, response
  buffer behavior, and trx_type gating are all
  correct before writing testbench vectors.

**Step 3 -- BP-039: tb_ittage.sv**
  Full testbench with pre-computed test vectors.
  Instantiates ittage.sv with actual ittage_table
  instances in the loop. Per BP-033-FIX-1 and
  BP-036 methodology: Test Vector Table with all
  expected values pre-computed in prompt. Separate
  from implementation prompts to reduce context
  pressure and correlated-bug risk.

  Apply Verilator stl_sequent rule from CLAUDE.md
  when writing testbench stimulus tasks.

  Arbitration tests required per bp_arb_spec.md
  section 10.3 (TB-ITTAGE-ARB-01 through
  TB-ITTAGE-ARB-08 equivalent).

  UAON trx_type gating: verify at concurrent
  pred+upd test cases that UAON always_ff block
  behavior is correct when trx_type=0 (PRED).

  Files needed:
    planning/arch/bp_arb_spec.md
    planning/interfaces/ittage_interfaces.md
    planning/interfaces/ittage_table_interfaces.md
    planning/arch/ittage_cntrl_decisions.md
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
    rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
    rtl/core/frontend/bpu/rtl/ittage_table.sv
    rtl/core/frontend/bpu/rtl/ittage_cntrl.sv
    rtl/core/frontend/bpu/rtl/ittage.sv
