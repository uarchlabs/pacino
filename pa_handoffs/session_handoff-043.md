<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 043
Written by Claude.ai at end of session-042.
Date: 2026-05-19

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-042 completed three tasks:
  - TD #47 closed: ittage_interfaces.md and
    tage_interfaces.md updated with pq_not_full
    and upd_rdy ports and semantics.
  - BP-038b complete: response buffer (RB) removed
    from ittage.sv. Dead logic confirmed and excised.
    Six active arbitration rules remain. Lint clean
    first attempt.
  - BP-039 complete: tb_ittage.sv written and
    passing. 13 test cases, 35 checks, zero warnings.
    Four DUT bugs found and fixed during testbench
    development.

---

## What This Session Accomplished

### TD #47 (closed)

ittage_interfaces.md and tage_interfaces.md both
updated to add pq_not_full and upd_rdy to the port
list with correct semantics. Ports confirmed against
RTL grep of ittage.sv. Trailing comma artifact on
folded_hist fixed in ittage_interfaces.md.

Semantic clarifications recorded:
  - ittage_upd_rdy_u1 is a flopped version of
    ittage_upd_val_u0. All updates complete in one
    cycle. No backpressure currently required.
    Consumer may ignore this signal.
  - pq_not_full: prediction queue not full.
    Consumer must gate pred_val_p0 on this signal.
  - upd_rdy: update queue not full. Consumer must
    gate upd_val_u0 on this signal.
  - Both ports pending rename per TD #49.

### TD #48 (closed)

RB confirmed as dead logic in ittage.sv.
consumer_ready=1'b1 hardwired internally. ITTAGE has
no SC consumer -- ITTAGE predicts targets for indirect
branches only; SC operates on conditional branches
only. These are mutually exclusive branch classes.

RB removed in BP-038b. TD #48 closed.

### BP-038b (complete)

Removed response buffer from ittage.sv. Changes:
  - RB_IDX_W, RB_PTR_W localparams removed.
  - rb_meta_mem, rb_val_mem, rb_head_r, rb_tail_r,
    rb_full, rb_empty, resp_buf_full_w removed.
  - rb_ff always_ff block removed.
  - rb_out_comb always_comb block removed.
  - Replaced with direct assigns:
      assign ittage_pred_rdy_p2 = cntrl_pred_rdy_p2;
      genvar loop for ittage_pred_meta_p2[s].
  - arb_comb Rules 3 and 5 simplified: resp_buf_full_w
    guards removed. Six active rules remain.
  - arb_cred_ff Rule 3 guard simplified.
  - File header updated with BP-038b note.
  - ITTAGE_RESP_BUF_DEPTH retained in
    bp_defines_pkg.sv -- not removed.

### BP-039 (complete)

tb_ittage.sv written. 13 test cases, 35 checks,
all passing. Zero warnings. FAST_INIT used throughout.
Round-trip hit methodology used for hit tests.

Test cases:
  TC-P01    PASS -- No-hit, slot 0 only
  TC-P02    PASS -- No-hit, both slots
  TC-P03    PASS -- Round-trip hit IT1 slot 0
  TC-P04    PASS -- CTR increment after correct pred
  TC-ARB-01 PASS -- Prediction only (10 predictions)
  TC-ARB-02 PASS -- Update only (5 updates)
  TC-ARB-03 PASS -- Simultaneous pred+upd, diff entry
  TC-ARB-04 PASS -- Simultaneous pred+upd, same entry
  TC-ARB-05 PASS -- UQ burst fill to depth 2
  TC-ARB-06 PASS -- PQ fills to depth 4
  TC-ARB-07 N/A  -- RB removed BP-038b
  TC-ARB-08 PASS -- Starvation prevention
  TC-UAON-01 PASS -- UAON gating concurrent pred+upd

Four DUT bugs found and fixed:

  Bug 1 -- ittage_cntrl.sv: branch_id pipeline timing.
  branch_id read from pred_inp_p0 at meta_p2_reg stage
  after input already deasserted. Fixed: branch_id_p1
  register added to capture at p1. meta_p2_reg reads
  branch_id_p1.

  Bug 2 -- ittage_cntrl.sv: alc_index_u0 wrong source.
  upd_sel computed alc_index_u0 from prm_idx/alt_idx
  (provider indices, zero for no-hit). Fixed:
  alc_index_u0 = ittage_pred_meta.ittage_alc_idx
  (the actual allocation index from prediction meta).

  Bug 3 -- ittage_table.sv: tbl_ri_active overrides
  write addr/data mux. With FAST_INIT=1, sram_init
  active signal remains high for full 512-cycle init
  sequence. addr_mux and din_mux used tbl_ri_active
  as top guard, forcing addr=0 and data=0 during
  normal allocation writes. Fixed: mux guards changed
  from tbl_ri_active to ri_we (= tbl_ri_active &
  tbl_ri_wr). With fast_init, ri_we=0 so normal
  paths are used.

  Bug 4 -- ittage_cntrl.sv: ctr_upd using_primary
  condition inverted. using_primary=1 branch was
  updating alt CTR; using_primary=0 branch was
  updating prm CTR. Branches swapped. Fixed:
  using_primary=1 now updates prm CTR,
  using_primary=0 updates alt CTR.

---

## Methodology Updates This Session

  1. Prompt template failure in first draft of
     BP-038b required two passes to correct. Template
     has been embedded explicitly in the handoff as
     mitigation. Effectiveness unverified -- first
     new-session use of embedded template has not
     occurred yet.

  2. Round-trip hit methodology confirmed workable
     for ittage testbench without hash knowledge.
     Seed prediction captures alc_comp/idx/tag.
     Allocation update uses captured values.
     Follow-up prediction with same PC hits.

  3. Test ordering dependency is a known weakness
     in tb_ittage.sv. TC-ARB-04 and TC-UAON-01
     depend on state from prior tests. To be
     addressed in cleanup session (TD #51 scope).

---

## Open Technical Debt

  - TD #43: ittage_pred_strong definition in
    ittage_cntrl_decisions.md incorrect. Needs
    update to CTR > 0 (not NULL). Deferred.
  - TD #44: ittage_cntrl_decisions.md decoration
    flags section needs correction when TD #43
    is implemented.
  - TD #45: TAGE T0 index handling needs revisit.
  - TD #46: REOPENED. tb_ittage_cntrl.sv missing
    trx_type port added in BP-038a. sim_ittage_cntrl
    fails with PINMISSING. Was incorrectly marked
    closed. Fix before next integration session.
  - TD #49: Arb queue status port renaming. Tage
    and ITTAGE pq_not_full and upd_rdy ports need
    standardized names with module prefix.
    Tage: pq_not_full -> tage_pq_not_full,
          upd_rdy     -> tage_uq_not_full.
    ITTAGE: pq_not_full -> ittage_pq_not_full,
            upd_rdy     -> ittage_uq_not_full.
    Scope: RTL, testbenches, planning docs.
    Defer to cleanup session before bp_cluster.
  - TD #50: sram_init FAST_INIT behavior. sram_init
    runs full init sequence even when FAST_INIT=1.
    active signal remains high for 512 cycles,
    overriding write mux paths (Bug 3, BP-039).
    When FAST_INIT=1, sram_init should not run its
    init sequence and active should not assert.
    Scope: sram_init.sv, ittage_table.sv.
    Audit tage_table.sv for same pattern.
  - TD #51: CTR/USE/TGT update rule audit. Bug 4
    (BP-039) found using_primary inverted in
    ittage_cntrl.sv ctr_upd block. Systematic risk
    that other update logic blocks (USE, TGT, alloc)
    may have similar errors. New round-trip test set
    required, one test per rule row in
    ittage_cntrl_ctr_update_rules.md and
    ittage_cntrl_use_update_rules.md. Tests must be
    independent of TC-P01 through TC-UAON-01.

---

## Next Session (043)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-043.md (this file)
  CLAUDE.md

Prompt template for Claude Code sessions:
=============================================================
# Task Header
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | <BLOCK-NUMBER>          | as needed                |
| Date         | YYYY.MM.DD              |                          |
| Module       | <module>                |                          |
| Run time     |                         |                          |
| Ctx %        |                         |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | <sha>                   |                          |
Task:   [ ] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Status: [ ] in-progress [ ] complete        [ ] abandoned
# Overview of task
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion
## Claude.code Console Output
## My Assessment
## Claude.ai Assessment
## Follow-on Actions
- [ ] As needed document here
## CLAUDE.md Updates
TBD as needed document here
## Other Planning File Updates
TBD as needed document here
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt
=============================================================
:: PROMPT:START ::
## Task ID
Replace this with the task ID
## Context Loaded
@File-Name replace with any files needed
## Hypothesis
## Background
## Binding Previous Decisions
## Specific Requirements
## Constraints
## Deliverables
Note: If a new module is to be created ensure that
claude.code is allowed or told to modify the Makefile
for lint checking at the minimum.
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
RESULTS NOT YET WRITTEN -- replace this line when filling in.
## Test Matrix (testbench sessions only, omit otherwise)
For each test case document:
- Test name
- Rule or rules exercised
- Setup: initial RAM state, struct fields driven
- Stimulus: which signals asserted and values
- Expected outcome: which RAM entries change and how
- Pass/fail criterion
## What was delivered
## Test Case Results
## Assumptions made not explicit in the prompt
## Decisions made not explicit in the prompt
## RVA23 compliance risks and gaps noticed
## Deferred Work
## Other Notes
:: RESULTS:END ::

### Planned work

**Step 1 -- Fix TD #46**
  tb_ittage_cntrl.sv missing trx_type port.
  Add trx_type input connection. Drive 1'b0 for
  existing tests (update path disabled). Verify
  all 76 existing tests still pass.
  Files needed:
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
    rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
    rtl/core/frontend/bpu/rtl/ittage_cntrl.sv
    rtl/core/frontend/bpu/tb/tb_ittage_cntrl.sv

**Step 2 -- Cleanup: TD #50 sram_init FAST_INIT**
  sram_init.sv: when FAST_INIT plusarg is present,
  suppress init sequence and hold active=0.
  ittage_table.sv: audit write mux guards now that
  Bug 3 fix is in place. Verify ri_we gating is
  correct in all paths.
  Audit tage_table.sv for same tbl_ri_active
  pattern.
  Files needed:
    rtl/core/frontend/bpu/rtl/sram_init.sv
    rtl/core/frontend/bpu/rtl/ittage_table.sv
    rtl/core/frontend/bpu/rtl/tage_table.sv
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv

**Step 3 -- Cleanup: TD #51 update rule audit**
  New round-trip test set for tb_ittage.sv.
  One test per rule row in:
    ittage_cntrl_ctr_update_rules.md
    ittage_cntrl_use_update_rules.md
  Tests must be self-contained and independent
  of each other and of TC-P01 through TC-UAON-01.
  Files needed:
    planning/arch/ittage_cntrl_ctr_update_rules.md
    planning/arch/ittage_cntrl_use_update_rules.md
    planning/arch/ittage_cntrl_decisions.md
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
    rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
    rtl/core/frontend/bpu/rtl/ittage.sv
    rtl/core/frontend/bpu/tb/tb_ittage.sv
