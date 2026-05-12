# tage_cntrl Allocation Rules
```
 FILE:    tage_cntrl_alloc_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-05
 CONTACT: Jeff Nye
```

---

## Scope

This document covers allocation candidate selection at predict
time and the allocation write at update time. It is a companion
to tage_cntrl_decisions.md and tage_table_interfaces.md.

---

## Trigger

Allocation fires during update when:
  cond_mispredict == 1
  AND tage_prm_comp < M  (provider is not the longest table)

Where M is the index of T4 (the longest history table).

If provider is T4 and mispredicts: update CTR only, no
allocation.

---

## Count

One entry allocated per misprediction event.

---

## Candidate Selection at Predict Time (p1, combinational)

Scan tables T(provider+1) through T4 for u_eff == 0.
u_eff is used for the useful == 0 test, not raw USEFUL.
No allocation in consecutive tables -- if Tj is selected,
Tj+1 is skipped even if u_eff == 0.
Select the shortest-history qualifying table.

If provider table is the last table, no allocation should
occur tage_alloc_comp should be set to zero.

tage_cntrl generates tage_alloc_idx directly (pre-hashed).
Source is the index_hash_p0 that drove the candidate table
during prediction. No rehashing at update time.

Captures into meta:
  tage_alloc_comp  -- table index of selected candidate.
                      Set to 0 (T0) when no candidate found.
  tage_alloc_idx   -- pre-hashed RAM index of candidate
  tage_alloc_tag   -- tag for the new entry, captured at
                      predict time

### No-candidate sentinel

tage_alloc_comp == 0 (T0) indicates no allocation candidate
was found. T0 is never a valid allocation target -- allocation
only targets tables longer than the provider. This sentinel
is unambiguous and consistent with the use of comp == 0 as
the tagged-table-miss indicator in the CTR update rules.

When tage_alloc_comp == 0 arrives at update time, alc_wr_u0
is suppressed for all tables. No allocation write is issued.

Epoch aging (EPC field) handles starvation prevention.
Useful bit decrement on failed allocation is not implemented.

---

## Initialization of Allocated Entry

CTR   = 3'b100  (weakest taken)
USE   = 2'b00   (null useful)
EPC   = current lcl_epoch value for the slot
TAG   = tage_alloc_tag from meta
VALID = 1'b1

---

## Allocation Write Data Assembly

The allocation write data is constructed per the entry layout
in tage_table_interfaces.md. TAG bits are the MSBs:

  [TAG, EPC, USE, CTR, VALID]

This maps directly to alc_wd_u0[ALLOC_DATA_WIDTH-1:0].

---

## Write Strobe Generation

alc_wr_u0[slot] is asserted at update time when:
  cond_mispredict == 1
  AND tage_prm_comp < M
  AND tage_alloc_comp != 0  (valid candidate was found)

The no-consecutive-table constraint is enforced at predict
time during candidate selection. The write strobe at update
time does not re-evaluate adjacency.

alc_wr_u0 is gated per table inside tage_table by comparing
THIS_TABLE to tage_alloc_comp (via prm_tbl_sel_u0). Only the
selected candidate table performs the write.

---

## EPC Field

The current lcl_epoch value for the slot is written to the
EPC field of the allocated entry at update time.
See tage_cntrl_useful_update_rules.md for aging rules.

