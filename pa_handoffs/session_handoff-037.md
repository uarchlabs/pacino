# Session Handoff 037
Written by Claude.ai at end of session-036.
Date: 2026-04-29

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-036 was productive with no major failures. All
planned steps were completed. The session recovered the
work that was degraded in session-035.

---

## What This Session Accomplished

### Step 1: TAGE use/uaon split fixes
  tage_cntrl_use_update_rules.md
    -- Header added (title, date, status, separator).
    -- Content verified: USE only, no UAON content.
    -- Status: Complete. Delivered as downloadable file.

  tage_cntrl_uaon_update_rules.md
    -- File label verified correct.
    -- Content verified: UAON only, no Useful content.
    -- Status: Draft. Delivered as downloadable file.

### Step 2: ITTAGE use/uaon split fixes
  ittage_cntrl_use_update_rules.md
    -- Header verified complete.
    -- Content verified: USE only, no UAON content.
    -- Status: Draft. Delivered as downloadable file.

  ittage_cntrl_uaon_update_rules.md
    -- 5 corrections applied:
       1. Title typo fixed (itage -> ittage)
       2. NOT WEAK replaced with NOT NULL throughout
       3. ittage_pred_strong redefined as NOT NULL
       4. Component selection trigger corrected to CTR==0
       5. Correctness definitions rewritten as target
          comparisons (resolved_target vs prm/alt tgt)
    -- Status: Draft. Delivered as downloadable file.

### Step 3: ittage_table_interfaces.md
    -- Created from manually authored draft.
    -- 5 corrections applied:
       1. Overview: direction -> target prediction
       2. Bank section: tage_bim reference removed
       3. THIS_TABLE range: T0-T4 -> IT0-IT5
       4. Derived params: IT_CNTRL_BITS_WIDTH and
          IT_ALLOC_DATA_WIDTH renamed from unprefixed
          versions. Confirmed as local parameters only,
          not global. THIS_CNTRL_BITS_WIDTH and
          THIS_ALLOC_DATA_WIDTH added to Internal
          Module Parameters by user.
       5. Tag widths corrected per bp_defines_pkg.sv:
          IT1-IT2=8b, IT3-IT4=9b, IT5=11b
       6. Update Interface unclosed code fence fixed
    -- Status: Draft. Delivered as downloadable file.

### Step 4: ITTAGE planning doc verification
  ittage_interfaces.md
    -- Consistency fixes applied (folded_hist port,
       UAON threshold operator, port naming).
    -- Status: Draft.

  ittage_cntrl_alloc_rules.md
    -- Verified consistent. No changes.
    -- Status: Complete.

  ittage_cntrl_ctr_update_rules.md
    -- Not modified this session.
    -- TBDs on rows 2 and 5 remain open.
    -- Status: Draft.

  ittage_cntrl_decisions.md
    -- 6 corrections applied:
       1. UAON trigger: 3'b011/3'b100 -> 3'b000
       2. UAON counter check: positive -> >=IT_UAON_THRES
       3. Alloc CTR init: 3'b100 -> 3'b000
       4. File ref: useful_update -> use_update
       5. Signal names: alloc -> alc throughout
       6. Stale open item 2 closed
    -- no_tagged_hit replaced with ittage_hit==0
       throughout.
    -- Status: Draft. 2 open items remain (see below).

  ittage_cntrl_uaon_update_rules.md
    -- See Step 2 above.

  ittage_cntrl_use_update_rules.md
    -- See Step 2 above.

  ittage_table_hash_rules.md
    -- Verified consistent. No changes.
    -- Status: Complete.

### Step 5: tage_interfaces.md corrections
  6 corrections applied:
    1. UAON trigger: null confidence -> weak (3'b011/3'b100)
    2. Signal name: ittage_pred_rdy -> tage_pred_rdy
    3. Branch type: indirect -> conditional
    4. Typo: ttage_cntrl -> tage_cntrl
    5. File ref: ittage_cntrl_alloc -> tage_cntrl_alloc
    6. Unclosed code fence in override chain fixed

### Step 5: PROJECT_STATUS.md
    -- Updated to session-036, 2026-04-29.
    -- Wrong ITTAGE file names corrected throughout.
    -- New TAGE planning doc entries added.
    -- ITTAGE doc statuses updated.
    -- Tech debts #43, #44, #45 added.

---

## Open Items Carried Forward

### ittage_cntrl_decisions.md open items
  1. ittage_table_interfaces.md -- created this session.
     Open item 1 is now closed.
  2. II6: tgt_wr_u0 gating. Genuinely unresolved.
     Retain until ittage_interfaces.md open items closed.

### ittage_cntrl_ctr_update_rules.md
  TBD rows 2 and 5: confirm pred_diff terminology.
  Note: ittage_cntrl_decisions.md settled this session
  that ITTAGE uses indir_mispredict not pred_diff.
  This TBD should close quickly when the file is loaded
  and compared against decisions.md.

### Tech debts open this session
  #43 -- tage_cntrl_use_update_rules.md needs background
         paragraph explaining the USE field purpose in
         tage table entries.
  #44 -- Claude Code verify USE update rules against RTL.
  #45 -- Claude Code verify UAON update rules against RTL.

---

## File Label Convention (established session-036)

All planning documents use this header format:

  # (title)
  ```
   FILE:    (file name)
   SOURCE:  (as needed)
   STATUS:  (as needed)
   UPDATED: (date)
   CONTACT: Jeff Nye
  ```

The old format `# File: filename` on line 1 is superseded
by this header block. All files processed this session
use the new format.

---

## Next Session (037)

### Suggested order (agreed end of session-036)

#### Step 1: Close ittage_cntrl_ctr_update_rules.md TBDs
Supply ittage_cntrl_ctr_update_rules.md and
ittage_cntrl_decisions.md. The TBD on rows 2 and 5
(pred_diff vs indir_mispredict) should close against
the decisions document. Verify no other open items.

#### Step 2: Close II6 -- tgt_wr_u0 gating
Supply ittage_interfaces.md and ittage_cntrl_decisions.md.
Resolve tgt_wr_u0 gating definition. Update both files.
Deliver as downloadable files.

#### Step 3: Tech debt #43
Add background paragraph to tage_cntrl_use_update_rules.md
explaining what the USE field is for in tage table entries.
Supply the file. Deliver corrected version.

#### Step 4: Tech debts #44 and #45
Claude Code tasks. Verify USE and UAON update rules
against current RTL. Run before redundancy pass so
verified state is known before collapsing content.

#### Step 5: Redundancy collapse pass
Load all ITTAGE planning documents simultaneously.
Identify and discuss methods to collapse redundant
content across files. High context cost -- do only
if context remains after Steps 1-4.

### Files needed at session start
  PROJECT_STATUS.md (updated)
  session_handoff-037.md (this file)
  CLAUDE.md

  For Step 1:
    ittage_cntrl_ctr_update_rules.md
    ittage_cntrl_decisions.md

  For Step 2:
    ittage_interfaces.md
    ittage_cntrl_decisions.md

  For Step 3:
    tage_cntrl_use_update_rules.md

  For Steps 4-5:
    All ITTAGE planning documents (supply as needed)

