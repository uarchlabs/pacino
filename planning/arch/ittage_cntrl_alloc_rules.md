# ittage cntrl Allocation Rules
```
 FILE:    ittage_cntrl_alloc_rules.md
 SOURCE:  various
 STATUS:  COMPLETE
 UPDATED: 2026-06-10
 CONTACT: Jeff Nye
```

---
## Scope
This document covers allocation candidate selection at predict
time and the allocation write at update time. It is a companion
to ittage_cntrl_decisions.md and ittage_table_interfaces.md.
---
## Trigger
Allocation fires during update when:
  indir_mispredict == 1
  AND ittage_prm_comp < M  (provider is not the longest table)
Where M is the index of IT5 (the longest history table).
If provider is IT5 and mispredicts: update CTR and target only,
no allocation.
---
## Count
One entry allocated per misprediction event.
---
## Candidate Selection at Predict Time (p1, combinational)
Scan tables IT(provider+1) through IT5 for u_eff == 0.
u_eff is used for the useful == 0 test, not raw USEFUL.
No allocation in consecutive tables -- if ITj is selected,
ITj+1 is skipped even if u_eff == 0.
Select the shortest-history qualifying table.
If provider table is the last table, no allocation should
occur and ittage_alc_comp should be set to zero.
ittage_cntrl generates ittage_alc_idx directly (pre-hashed).
Source is the idx_hash_p0 that drove the candidate table
during prediction. No rehashing at update time.
Captures into meta:
  ittage_alc_comp  -- table index of selected candidate.
                        Set to 0 (IT0 placeholder) when no
                        candidate found.
  ittage_alc_idx   -- pre-hashed RAM index of candidate
  ittage_alc_tag   -- tag for the new entry, captured at
                        predict time
### No-candidate sentinel
ittage_alc_comp == 0 (IT0 placeholder) indicates no
allocation candidate was found. IT0 is never a valid
allocation target -- allocation only targets tables longer
than the provider. This sentinel is unambiguous.
When ittage_alc_comp == 0 arrives at update time,
alc_wr_u0 is suppressed for all tables. No allocation write
is issued. Epoch aging (EPC field) handles starvation
prevention.
Useful bit decrement on failed allocation is not implemented.
---
## No-hit Allocation
When ittage_pred_rdy was 0 at predict time (no table hit),
allocation scans from IT1. The no-consecutive-table constraint
still applies.
---
## Initialization of Allocated Entry
CTR    = 3'b000  (null confidence)
USE    = 2'b00   (null useful)
EPC    = current lcl_epoch value for the slot
TAG    = ittage_alc_tag from meta
TGT    = resolved_target from execute
VALID  = 1'b1
---
## Allocation Write Data Assembly
The allocation write data is constructed per the entry layout
in ittage_table_interfaces.md. TAG bits are the MSBs:
  [TAG, EPC, USE, CTR, TGT, VALID]
This maps directly to alc_wd_u0[IT_ALLOC_DATA_WIDTH-1:0].
---
## Write Strobe Generation
alc_wr_u0[slot] is asserted at update time when:
  indir_mispredict == 1
  AND ittage_prm_comp < M
  AND ittage_alc_comp != 0  (valid candidate was found)
The no-consecutive-table constraint is enforced at predict
time during candidate selection. The write strobe at update
time does not re-evaluate adjacency.
alc_wr_u0 is gated per table inside ittage_table by comparing
THIS_TABLE to ittage_alc_comp (via alc_tbl_sel_u0). Only
the selected candidate table performs the write.
---
## EPC Field
```
The current lcl_epoch value for the slot is written to the
EPC field of the allocated entry at update time.
See ittage_cntrl_use_update_rules.md for aging rules.
