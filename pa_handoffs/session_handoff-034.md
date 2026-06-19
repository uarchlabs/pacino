<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 034
Written by Claude.ai at end of session-033.
Date: 2026-04-27

This session completed the ITTAGE research phase and produced
the full set of ITTAGE planning documents. ittage_interfaces.md
was written but has known issues requiring revision next session.
bp_structs_pkg.sv was updated with ITTAGE structs but the IT5
fold field fix and comment correction are still pending.
Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-033.

### Step 1: Planning doc updates

User confirmed planning doc updates from session-032 were
applied before this session began.

### ITTAGE research -- all 6 questions resolved

All research questions from the handoff-033 next-session
plan were closed:

  Q1: History lengths -- IT1-IT5: 4, 8, 13, 16, 32.
      Fits GHR_WIDTH=256.
  Q2: Tag widths -- 8, 8, 9, 9, 11 per table.
  Q3: Target storage -- 38 bits (upper 38b of Sv39 VA,
      bit 0 not stored). IT_TBL_TGT_WIDTH parameter
      array added to bp_defines_pkg.sv.
  Q4: Table count -- 5 active tables IT1-IT5, IT0
      placeholder only.
  Q5: RAS interaction -- mutually exclusive by branch
      type resolved upstream. No dynamic arbitration.
  Q6: Update policy -- target written on misprediction
      only, and only when provider CTR is null.
  Q7: No-hit fallback -- falls through to FTB target.
      (Added during research, not in original 6.)

Additional decisions made during research:

  - VA_WIDTH=40 retained. Sv39 requires 39 bits.
    Bit 0 always zero for instruction alignment.
    38 bits is the correct stored target width.
  - RVA23 mandates Sv39. Sv48 and Sv57 are optional
    expansion options.
  - ITTAGE operates at s2 alongside FTB and TAGE,
    not s3 as previously assumed. Tech debt #42 added:
    pipeline diagram shows ITTAGE at s3, should be s2.
  - BrIMLI parameter contamination identified and
    corrected. IT5 is a standard tagged table with
    HIST=32, not BrIMLI. BrIMLI belongs to SC only.

### SC parameters recovered

SC parameters recovered from the cz_bpu_stat_corr_1t
design file and XiangShan documentation:

  SC_NUM_TABLES = 5 (4 global-history + 1 BrIMLI)
  SC_TBL_CTR[0:4]   = '{6, 6, 6, 6, 6}
  SC_TBL_IDX[0:4]   = '{9, 9, 9, 9, 10}
  SC_TBL_HIST[0:4]  = '{0, 4, 16, 64, 0}
  SC_IMLI_INDEX_BITS = 10
  SC_LO_THRESHOLD = 25
  SC_HI_THRESHOLD = 35
  No tag bits. All tables are pure counter arrays.

bp_defines_pkg.sv SC parameter block corrected:
  SC_MAX_FH = 64 (was 9 -- wrong)
  SC_MAX_FH1 = 0 (was 9 -- SC has no tag folds)
  SC_MAX_FH2 = 0 (was 8 -- SC has no tag folds)
  SC_MAX_VAL_WIDTH = 0 (was 1 -- SC has no valid bit)
  SC_TBL_CTR[4] = 6 (was 3 -- all tables are 6b)

### ITTAGE planning documents written

The following planning documents were produced:

  planning/interfaces/ittage_interfaces.md
    -- Draft. Has known issues requiring revision.
    -- See pending fixes section below.

  planning/rules/ittage_cntrl_alloc_rules.md
    -- Complete. Converted from tage version.

  planning/rules/ittage_cntrl_ctr_update_rules.md
    -- Draft. Two TBD items in rows 2 and 5.
    -- See TBD items section below.

  planning/rules/ittage_cntrl_decisions.md
    -- Draft. Three open items.
    -- See open items section below.

  planning/rules/ittage_cntrl_uaon_useful_rules.md
    -- Draft. One TBD item (correctness definition).

  planning/rules/ittage_cntrl_useful_update_rules.md
    -- Draft. One TBD item (pred_diff definition).

  planning/rules/ittage_table_hash_rules.md
    -- Complete. Converted from tage version.

### bp_structs_pkg.sv updated

  ittage_pred_inp_t added.
  ittage_pred_meta_t added with full alt-provider fields.
  ittage_upd_inp_t added.
  bp_ftq_meta_t updated to include ittage_pred_meta_t.
  bp_ittage_meta_t removed (redundant with br_type in
    bp_ftq_entry_t).

### Anti-patterns added

  PG-004: Design decision stated without source citation.
  PG-005: Uncertainty not flagged before writing
          deliverable.
  Both added to PROJECT_STATUS.md anti-pattern section.

---

## Pending Fixes -- First Task of Session-034

### ittage_interfaces.md

The following issues were identified during review and
must be fixed before the document is used as a prompt
input:

  1. Module Parameters section: replace parameter array
     listings with a reference to bp_defines_pkg.sv
     ITTAGE parameters section. Follow the same
     convention as the corrected tage_interfaces.md.

  2. Internal Module Parameters section: remove. These
     are implementation details not visible at the
     interface boundary.

  3. Consumer note: change to
     "Consumer: BP cluster (p2 target mux, FTQ write)"

  4. Prediction semantics block: remove the two extra
     lines added to ittage_pred_rdy_p2=1 and =0.
     ittage_pred_rdy_p2 follows ittage_pred_val_p0
     through the pipeline. Hit status is in
     ittage_hit in the metadata. Match TAGE pattern.

  5. UAON update rules paragraph: remove from
     ittage_interfaces.md. Move to
     ittage_cntrl_uaon_useful_rules.md which already
     covers this.

  6. IT1-IT5 Port List section: move to
     ittage_table_interfaces.md (not yet written).

  7. Open items table: replace with the three confirmed
     open items only: II2, II3, II4.
     II1 (IT5 fold fields): fix bp_structs_pkg.sv.
     II5 (no-hit scan): close, defined in alloc rules.
     II6 (tgt_wr_u0 gating): retain as open item,
     it is genuinely unresolved.

### bp_structs_pkg.sv

  1. Add it_t5_idx_fh, it_t5_tag_fh1, it_t5_tag_fh2
     to bp_folded_hist_t.
  2. Correct the comment "IT5 is BrIMLI -- no folds"
     to "IT5 is a standard tagged table with HIST=32."

---

## TBD Items in Planning Documents

### ittage_cntrl_ctr_update_rules.md

  Row 2, Action(alt): On primary provider misprediction
  when alt target differed -- should the alternate CTR
  be updated? Confirm whether ITTAGE confidence counter
  semantics follow TAGE direction counter semantics here.

  Row 5, Action(primary): Symmetric case to row 2.

### ittage_cntrl_decisions.md

  Concurrent CTR and TGT write mutual exclusivity:
  From Seznec, on misprediction, if CTR non-null:
  decrement CTR (no target write); if CTR null: replace
  target (CTR stays at null, no CTR write). These appear
  mutually exclusive. Confirm before ittage_cntrl RTL.

  pred_diff definition: confirm target mismatch not
  direction mismatch (ittage_pred_tgt != ittage_alt_tgt).

### ittage_cntrl_uaon_useful_rules.md

  Correctness definitions: confirm prm_correct and
  alt_correct use target match not direction match.

---

## Document Still Required

  ittage_table_interfaces.md -- not yet written.
  Analogous to tage_table_interfaces.md. Must be
  written before ittage_cntrl RTL begins. Receives
  the IT1-IT5 port list moved out of
  ittage_interfaces.md.

---

## Decisions Made This Session

### ITTAGE at s2 not s3

Pipeline diagram error identified. ITTAGE operates at
s2 alongside FTB and TAGE. Tech debt #42 added.

### alt_ctr_wr_u0 present in ittage_table

Both prm_ctr_wr_u0 and alt_ctr_wr_u0 are real and
active write paths. They are mutually exclusive -- never
both asserted in the same cycle -- but both are used.
Structural commonality with TAGE control is preserved.

### Target update policy

Target field written on misprediction AND CTR null only.
Per Seznec: non-null CTR on misprediction decrements CTR,
does not update target. CTR must reach zero before target
is replaced.

### Tables to exceed 80 columns

Markdown tables are exempt from the 80-column rule.
The constraint applies to code and prose only.

---

## Technical Debt Status After This Session

New debt added:
  #42 -- Pipeline diagram shows ITTAGE at s3, should
         be s2. Revisit after SC definition. Update
         diagram and discussions.

Still open (unchanged):
  #1  -- NUM_PRED_SLOTS=2 generate cleanup deferred
  #7  -- curs/curs_v rollback undefined
  #38 -- Verilator pinned to 5.020
  #39 -- TB-ARB-08 Rule 2 starvation untestable
  #40 -- TB-ARB-05 spec backpressure discrepancy
  #41 -- CU-08/CU-09 aging deferral

---

## Files Modified This Session

  rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
    -- ittage_pred_inp_t added
    -- ittage_pred_meta_t added (full alt-provider)
    -- ittage_upd_inp_t added
    -- bp_ftq_meta_t: ittage_pred_meta_t field added
    -- bp_ittage_meta_t removed
    -- IT5 fold fields and comment fix: PENDING

  Pending:
    rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
      -- SC parameter corrections noted above
      -- IT_TBL_TGT_WIDTH parameter array

  New planning documents (all in planning/):
    interfaces/ittage_interfaces.md (needs revision)
    rules/ittage_cntrl_alloc_rules.md
    rules/ittage_cntrl_ctr_update_rules.md
    rules/ittage_cntrl_decisions.md
    rules/ittage_cntrl_uaon_useful_rules.md
    rules/ittage_cntrl_useful_update_rules.md
    rules/ittage_table_hash_rules.md

---

## Next Session (034)

### Step 1: Apply pending fixes

  bp_structs_pkg.sv:
    - Add IT5 fold fields to bp_folded_hist_t
    - Fix IT5 BrIMLI comment

  bp_defines_pkg.sv:
    - Apply SC parameter corrections
    - Confirm IT_TBL_TGT_WIDTH present

  ittage_interfaces.md:
    - Apply the 7 fixes listed in pending fixes section

### Step 2: Resolve TBD items

  Resolve ctr_update_rules rows 2 and 5 using Seznec.
  Resolve concurrent CTR/TGT write mutual exclusivity.
  Resolve pred_diff and correctness definition for UAON.

### Step 3: Write ittage_table_interfaces.md

  Analogous to tage_table_interfaces.md. Receives
  the IT1-IT5 port list from ittage_interfaces.md.
  Must include:
    - Port list for ittage_table
    - Bank address assignment
    - Entry format
    - tbl_ri port semantics
    - Misc port semantics

### Step 4: Review all ITTAGE documents for consistency

  Cross-check all six planning documents against each
  other and against ittage_interfaces.md and
  ittage_table_interfaces.md before any RTL prompt
  is written.

