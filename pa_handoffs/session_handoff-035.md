<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 035
Written by Claude.ai at end of session-034.
Date: 2026-04-27

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

This handoff was hand modified, the PA could not
reason about the solution to the files with
redundant information.

Claude.ai made repeated errors with simple
file names, this:

xxx cntrl_uaon_update_rules.md

was turned into this, many times (6 times in this file alone)

xxx cntrl_uaon_useful_rules.md


This is a huge weakness in this methodology
without a known solution.

---

## What This Session Covered

Session context restored from session_handoff-034.

### Step 1: Pending fixes applied

  bp_structs_pkg.sv:
    -- IT5 fold fields added to bp_folded_hist_t:
       it_t5_idx_fh, it_t5_tag_fh1, it_t5_tag_fh2
    -- Comment corrected: "IT5 is BrIMLI -- no folds"
       changed to "IT5 is a standard tagged table
       with HIST=32"

  bp_defines_pkg.sv:
    -- SC parameter corrections applied:
       SC_MAX_FH=64, SC_MAX_FH1=0, SC_MAX_FH2=0,
       SC_MAX_VAL_WIDTH=0, SC_TBL_CTR[4]=6
    -- IT_TBL_TGT_WIDTH parameter array confirmed present

  ittage_interfaces.md:
    -- All 7 fixes from handoff-034 applied.
    -- pred_rdy deassert error corrected throughout.
       ittage_pred_rdy_p2 follows ittage_pred_val_p0
       through the pipeline. Asserts regardless of hit
       status. Hit status carried in no_tagged_hit.
    -- Consumer Obligations updated to reference
       no_tagged_hit instead of pred_rdy=0.
    -- no_tagged_hit added to ittage_pred_meta_t
       description.
    -- II6 confirmed closed (tgt_wr_u0 gating resolved
       by CTR update rules and decisions doc).
    -- resoluition typo fixed.

### Step 2: TBD items resolved

  ittage_cntrl_ctr_update_rules.md:
    -- Rows 2 and 5 resolved.
    -- pred_diff retired. ITTAGE uses indir_mispredict.
       There is no pred_diff in ITTAGE.
    -- V condition typo fixed: was no_tagged_hit==1,
       corrected to no_tagged_hit==0.
    -- no_tagged_hit tech debt noted: prediction response
       must assert no_tagged_hit when all IT1-IT5 tables
       miss. Added to tech debt tracking.

  ittage_cntrl_decisions.md:
    -- All fixes applied and file delivered.
    -- pred_rdy deassert error corrected in three places.
    -- Derived Signal section (pred_diff) removed.
    -- Concurrent CTR/TGT write mutual exclusivity
       confirmed closed from Seznec.
    -- Open items table cleaned up.

  ittage_cntrl_uaon_update_rules.md:
    -- Correctness definitions confirmed: prm_correct
       and alt_correct use target match not direction
       match. resolved_target vs ittage_prm/alt_tgt.
    -- UAON threshold confirmed: >= IT_UAON_THRES.
    -- TD column added to useful update table:
       ittage_pred_tgt != ittage_alt_tgt.
       Useful update suppressed when primary and
       alternate predicted same target.
    -- TTM replaced with NTH (no_tagged_hit).
    -- cond_mispredict replaced with indir_mispredict.
    -- File delivered.

  ittage_cntrl_useful_update_rules.md:
    -- Produced early in this session before
       ittage_cntrl_uaon_update_rules.md was written.
    -- See UNRESOLVED ISSUE below.

### Step 3: ittage_table_interfaces.md

  NOT STARTED. Still a hard blocker for RTL.

---

## UNRESOLVED ISSUE -- Document Redundancy

### The problem

THIS IS THE BROKEN SOLUTION FROM CLAUDE AI:

Two ITTAGE documents now cover the same useful counter
material:

  ittage_cntrl_uaon_update_rules.md
    -- Contains both UAON rules and useful counter
       rules. Matches the TAGE convention.

  ittage_cntrl_useful_update_rules.md
    -- Contains useful counter rules only.
    -- Produced early this session before the combined
       document existed.
    -- Is a strict subset of the combined document.

The TAGE convention (tage_cntrl_uaon_update_rules.md)
puts both UAON and useful rules in one document. The
standalone useful document has no TAGE precedent.

The same redundancy may exist on the TAGE side:
  tage_cntrl_uaon_update_rules.md -- combined
  tage_cntrl_useful_update_rules.md -- if it exists,
    it is redundant by the same argument.

### THE SOLUTION FROM THE USER
```
The user will supply tage_cntrl_use_update_rules.md
and                  tage_cntrl_uaon_update_rules.md

Resolve these two files do that only issues related to useful field
updates are retained in the tage_cntrl_use_update_rules.md

modify tage_cntrl_uaon_update_rules.md to retain only guidance 
related to uaon updates.

tage_cntrl_use_update_rules.md is the definitive source for
useful field updates.

tage_cntrl_uaon_update_rules.md is the definitive source for
uaon udpates.

The same task needs to be done for the ittage files as well.


### What was NOT resolved

This was discussed at length this session but was not
definitively resolved due to repeated analysis errors
on Claude's part. The correct resolution was never
confirmed by the user.

### First task of session-035

THESE ARE STUPID and POINTLESS QUESTIONS FROM CLAUDE AI:

Confirm with the user:
  1. Does tage_cntrl_useful_update_rules.md exist on
     disk?
  2. If yes, is it redundant with
     tage_cntrl_uaon_update_rules.md?
  3. Should ittage_cntrl_useful_update_rules.md be
     deleted as redundant?

Do not guess. Ask directly and record the answer before
touching any files.

---

## Reasoning Skills Issue -- Flagged for Session-035

Claude repeatedly flip-flopped on the document redundancy
question this session instead of reasoning from first
principles and committing to an answer. The pattern was:

  1. User asks a question.
  2. Claude gives an answer.
  3. User pushes back.
  4. Claude reverses without re-examining the evidence.
  5. Repeat.

The correct approach is:
  1. Identify the source of truth (TAGE convention).
  2. Reason from it explicitly.
  3. Commit to the answer.
  4. If wrong, ask what the correct source of truth is
     before reversing.

This must not recur in session-035.

---

## New Tech Debt Added This Session

  #43 -- no_tagged_hit must be asserted in ITTAGE
         prediction response when all IT1-IT5 tables
         miss. Required by handshake contract --
         pred_rdy asserts on every valid response.
         no_tagged_hit is the miss indicator, not
         pred_rdy deassertion.
         Affects: ittage_pred_meta_t, ittage_cntrl.sv,
         ittage.sv. Resolve before ittage_cntrl RTL
         prompt is written.

---

## Files Delivered This Session

  planning/interfaces/ittage_interfaces.md
    -- All 7 handoff-034 fixes applied. Status: Draft.
    -- Open items: II2, II3, II4.

  planning/rules/ittage_cntrl_ctr_update_rules.md
    -- Rows 2/5 resolved. V condition typo fixed.
    -- pred_diff retired. Status: Complete.

  planning/rules/ittage_cntrl_decisions.md
    -- All fixes applied. pred_diff removed.
    -- pred_rdy errors corrected. Status: Draft.
    -- Open items: 1, 2, 3 (see file).

  planning/rules/ittage_cntrl_uaon_update_rules.md
    -- Converted from TAGE version. TD column added.
    -- Correctness definitions confirmed target-based.
    -- Status: Draft.

  planning/rules/ittage_cntrl_useful_update_rules.md
    -- Status: REDUNDANCY UNRESOLVED. See above.

---

## Next Session (035)

### Step 1: Resolve document redundancy

  Confirm status of tage_cntrl_useful_update_rules.md
  and ittage_cntrl_useful_update_rules.md before any
  other work. See UNRESOLVED ISSUE section above.

### Step 2: Write ittage_table_interfaces.md

  Hard blocker for RTL. Must include:
    -- Port list for ittage_table (moved from
       ittage_interfaces.md)
    -- Bank address assignment
    -- Entry format
    -- tbl_ri port semantics
    -- Misc port semantics
  Analogous to tage_table_interfaces.md.

### Step 3: Cross-document consistency review

  Cross-check all ITTAGE planning documents against
  each other and against ittage_interfaces.md and
  ittage_table_interfaces.md before any RTL prompt
  is written.

### Step 4: Update PROJECT_STATUS.md

  -- Add tech debt #43 (no_tagged_hit)
  -- Update module status table for ITTAGE documents
  -- Mark completed items in open items table

