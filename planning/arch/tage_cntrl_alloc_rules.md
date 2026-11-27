<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# tage_cntrl Allocation Rules
```
 FILE:    tage_cntrl_alloc_rules.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-11-27
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
Source is the idx_hash_p0 that drove the candidate table
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

CTR   = resolved_taken ? 3'b100 : 3'b011  (weak toward the
        resolved direction)
USE   = 2'b00   (null useful)
EPC   = current lcl_epoch value for the slot
TAG   = tage_alloc_tag from meta
VALID = 1'b1

PERF-005 R4, BUILT, FOR ACCEPTANCE (tage_cntrl.sv alc_upd_comb). CTR
read 3'b100 (weakest taken) whatever the branch did, so an entry
allocated for a not-taken branch predicted taken on its first use;
14,110,629 of 26,871,877 allocations over the 105 traces (52.5%) were
for a not-taken resolution. cbp2016 allocates weak toward the outcome
(cbp2016_tage_sc_l.h 1460, 1505). Measured alone: 50Perc conditional
MPKI -0.0733, cycles -0.111%.

---

## Allocation Write Data Assembly

The allocation write data is constructed per the entry layout
in tage_table_entry_formats.md, which owns it; this cited
tage_table_interfaces.md, whose Entry Formats section points
there and carries no layout. Session-072. TAG bits are the MSBs:

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
THIS_TABLE to tage_alloc_comp, presented as alc_tbl_sel_u0
(tage_table_interfaces.md). Only the selected candidate table
performs the write. This read "via prm_tbl_sel_u0", the provider's
selector, which names the wrong table. Session-071.

---

## EPC Field

The current lcl_epoch value for the slot is written to the
EPC field of the allocated entry at update time.
See tage_cntrl_use_update_rules.md for aging rules. This named
tage_cntrl_useful_update_rules.md, which does not exist.
Session-072.

  2026-11-27  session-087, after PERF-005, for acceptance.
              Initialization: CTR weak toward the resolved direction
              (R4).
