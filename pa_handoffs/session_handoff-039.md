# Session Handoff 039
Written by Claude.ai at end of session-038.
Date: 2026-04-29

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

---

## Session Summary

Session-038 was productive with no failures. The planned
redundancy collapse pass was completed across all eight
ITTAGE planning documents. An unplanned but high-value
PROJECT_STATUS.md size reduction was also completed,
producing three new files and updating two existing ones.

---

## What This Session Accomplished

### Step 1: ITTAGE planning document redundancy collapse

All eight ITTAGE planning documents loaded simultaneously.
Redundancy identified, discussed, and collapsed.

Files modified:

  ittage_interfaces.md
    -- Bank Address Assignment section replaced with
       one-line cross-ref to ittage_table_interfaces.md.
    -- Provider selection: implementation detail removed
       (scan direction, hit vector MSB ordering). Consumer-
       visible behavior retained. Cross-refs added to
       ittage_cntrl_decisions.md and
       ittage_cntrl_uaon_update_rules.md.
    -- Delivered as downloadable file.

  ittage_table_interfaces.md
    -- Port Naming Convention section replaced with
       one-line cross-ref to ittage_interfaces.md.
    -- tgt_wr_u0 port semantics note extended with
       explicit cross-ref to ittage_interfaces.md
       Target Write Gating section.
    -- Bank Address Assignment retained as authoritative.
    -- Delivered as downloadable file.

  ittage_cntrl_decisions.md
    -- use_alt_on_na Counters: mux pseudocode and
       ittage_using_primary statement removed. Cross-ref
       to ittage_cntrl_uaon_update_rules.md added.
       Counter count, width, threshold, initial value,
       ownership, trigger condition retained.
    -- CTR Update Rules: indir_mispredict vs pred_diff
       note removed (lives in ctr_update_rules.md).
       Case analysis and cross-ref retained.
    -- Target Update Rules: collapsed to one sentence
       plus cross-ref to ittage_interfaces.md
       Target Write Gating section.
    -- Delivered as downloadable file.

Files not modified (intentionally):
  ittage_cntrl_alloc_rules.md
  ittage_cntrl_ctr_update_rules.md
  ittage_cntrl_uaon_update_rules.md
  ittage_cntrl_use_update_rules.md
  ittage_table_hash_rules.md

Intentional multi-location content (not collapsed):
  CTR/TGT mutual exclusion: retained in decisions.md,
  ittage_interfaces.md, and ittage_table_interfaces.md.
  Safety property -- three locations accepted.

---

### Step 2: PROJECT_STATUS.md size reduction

Five reductions applied. Three new files created.

  Reduction 1: Anti-patterns extracted.
    -- PG-001 through PG-005 moved to new file.
    -- PROJECT_STATUS.md Prompt Generation Guide
       section replaced with two-line reference.
    -- New file: PROMPT_ANTIPATTERNS.md

  Reduction 2: Prompt Generation Guide moved.
    -- Content moved to PROJECT_CORE.md as new
       subsection: Prompt generation rules.
    -- Reference to PROMPT_ANTIPATTERNS.md added
       at end of that subsection.
    -- PROJECT_STATUS.md section replaced with
       two-line reference to PROJECT_CORE.md.

  Reduction 3: TAGE decomposition log collapsed.
    -- BP-006 through BP-030 per-step notes removed
       from PROJECT_STATUS.md.
    -- Content archived in new TAGE_DECOMP_LOG.md.
    -- MODULE STATUS table rows for tage_table.sv,
       tage_bim.sv, tage_cntrl.sv, tage.sv trimmed
       to current state only. Active debts retained.
    -- New file: TAGE_DECOMP_LOG.md

  Reduction 4: Closed debt rows removed.
    -- Debts #43, #44, #45 removed from debt table.
       All three closed in sessions 037/BP-031/BP-032.

  Reduction 5: Completed module notes trimmed.
    -- bp_defines_pkg.sv, bp_structs_pkg.sv reduced
       to current state summary.
    -- loop_pred.sv, tage_interfaces.md notes trimmed.
    -- tage_cntrl_use_update_rules.md and
       tage_cntrl_uaon_update_rules.md: stale debt
       references corrected to closed status.

---

## Open Items Carried Forward

None. All session-037 carried items resolved.
No new open items from session-038.

---

## New Files Created This Session

  PROMPT_ANTIPATTERNS.md  -- PG-001 through PG-005.
                             Load when writing or
                             reviewing prompts only.
  TAGE_DECOMP_LOG.md      -- Archive of TAGE per-step
                             notes. Not updated after
                             extraction.

## Files Updated This Session

  ittage_interfaces.md         -- redundancy collapse
  ittage_table_interfaces.md   -- redundancy collapse
  ittage_cntrl_decisions.md    -- redundancy collapse
  PROJECT_STATUS.md            -- size reduction
  PROJECT_CORE.md              -- prompt gen rules added

---

## Next Session (039)

ITTAGE planning documents are complete and
redundancy-collapsed. RTL implementation can begin.

Suggested first step: ittage_table.sv.
  -- Implement a single ittage_table instance.
  -- Local hash functions per ittage_table_hash_rules.md.
  -- Port list per ittage_table_interfaces.md.
  -- Entry format per ittage_table_interfaces.md
     Entry Format section.
  -- Bank address assignment per
     ittage_table_interfaces.md Bank Address Assignment.
  -- Two bw_ram instances, one per prediction slot.

### Files needed at session start
  PROJECT_STATUS.md (this session's version)
  session_handoff-039.md (this file)
  CLAUDE.md

  For ittage_table.sv implementation:
  ittage_table_interfaces.md
  ittage_table_hash_rules.md
  bp_defines_pkg.sv
  bp_structs_pkg.sv

