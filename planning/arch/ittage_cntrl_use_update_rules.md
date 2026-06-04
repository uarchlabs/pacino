# ittage_cntrl Useful Counter Update Rules
```
 FILE:    ittage_cntrl_use_update_rules.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-06-03
 CONTACT: Jeff Nye
```

---

## Background

Each tagged ITTAGE table entry (IT1-IT5) contains a 2-bit USEFUL
counter field. The USEFUL field records whether an entry has recently
provided a correct prediction that disagreed with the alternative
provider. An entry with a non-zero USEFUL value has demonstrated
recent predictive value and is protected from eviction during
allocation. An entry whose USEFUL value has decayed to zero is a
candidate for replacement.

The epoch-based aging mechanism described below allows this
protection to decay over time without requiring explicit per-entry
writes: as the lcl_epoch counter advances, the effective USEFUL
value (u_eff) seen by the allocation logic decreases for entries
that have not been recently updated, making them eligible for
eviction even if their raw USEFUL field is non-zero.

USEFUL is updated only when the primary and alternate providers
predict different targets -- when they agree, no information about
relative provider quality is available and no update is performed.

Note: Seznec's original ITTAGE uses a 1-bit U field with a global
TICK-based reset. This implementation extends U to 2 bits with
INC/DEC semantics, consistent with the TAGE useful counter
extension used in this project.

---

## Useful Counter Aging

The ITTAGE predictor periodically ages the USEFUL counters in
table entries. Useful aging gradually removes replacement
protection from predictor entries that have not recently
demonstrated value, allowing stale entries to be evicted
(allocated) in favor of new ones without explicitly clearing
the tables.

Aging is a two-phase process that fits within the existing
prediction request/update request process. During prediction
requests, the EFFECTIVE useful bits are used to determine
which entry across the tables is the target for
replacement/allocation. The EFFECTIVE useful bits are the
aged view of the USEFUL bits across the entries.

The EFFECTIVE USEFUL values are returned in the prediction
response and used in the subsequent update phase.

---

There is an enable bit, ittage_enable_aging, as a primary
input to ittage and ittage_cntrl.

There is a 32b bus that supplies the aging interval as a
primary input to ittage and ittage_cntrl, called
ittage_aging_interval.

There are two local 32b registers in ittage_cntrl that hold
the running interval count, called lcl_aging_interval_0 and
lcl_aging_interval_1. Each register serves one of the two
prediction slots.

There are local 2b registers in ittage_cntrl that hold the
running epoch count, called lcl_epoch_0 and lcl_epoch_1.
Each register serves one of the two prediction slots.

---

## Interval and Epoch Operation

On reset: lcl_aging_interval_0 and lcl_aging_interval_1 are
loaded with the current value of ittage_aging_interval.

lcl_aging_interval_0 decrements on each assertion of
ittage_pred_rdy_0_p2.

lcl_aging_interval_1 decrements on each assertion of
ittage_pred_rdy_1_p2.

When lcl_aging_interval_0 reaches zero:
  lcl_epoch_0 increments (2b wrapping).
  lcl_aging_interval_0 reloads from ittage_aging_interval.

When lcl_aging_interval_1 reaches zero:
  lcl_epoch_1 increments (2b wrapping).
  lcl_aging_interval_1 reloads from ittage_aging_interval.

Aging is only active when ittage_enable_aging is asserted.

---

## Aging Disabled

When ittage_enable_aging=0 the epoch mechanism is inactive.
The effective USEFUL value is always equal to the raw USEFUL
field:

    u_eff = USEFUL  (aging disabled, equivalent to age==0 path)

Manual tests are expected to run with ittage_enable_aging=0.
A test failure under this condition indicates a table rule
violation, not an aging interaction.

---

## Effective Useful Computation

At predict time, ittage_cntrl computes u_eff for the primary
and alternative components using the slot's lcl_epoch register.

```
age = (IT_AGE_EPOCH - EPOCH) mod 4

if (age == 0) u_eff = USEFUL
if (age == 1) u_eff = USEFUL >> 1
else          u_eff = 0
```

Where:
  IT_AGE_EPOCH = lcl_epoch_0 or lcl_epoch_1 for the slot
  EPOCH        = EPC field of the RAM entry
  USEFUL       = USE field of the RAM entry

u_eff is a 2b saturating value.

The provider component's modified u_eff is returned in the
prediction response (ittage_pred_meta) on ittage_prm_useful
and ittage_alt_useful.

On the subsequent update, u_eff is written back to the USEFUL
field of the entry. The values are carried in the update data:

  ittage_upd_inp[s].ittage_pred_meta.ittage_prm_useful
  ittage_upd_inp[s].ittage_pred_meta.ittage_alt_useful

Which field is written (prm or alt) is determined by the
table below. The current lcl_epoch value is written to the
EPC field of the entry at the same time.

Theory: since lcl_epoch_0/1 is used to form u_eff, the
simple action of incrementing IT_AGE_EPOCH effectively ages
all entries in all tables without the need to update each
entry individually.

---

## Useful Counter Update Table

This table is entered when pred_src == PRED_ITTAGE. Signals
are prefixed by ittage_upd_inp_u0[s].ittage_pred_meta unless
otherwise noted. Prefix removed from column headers for
brevity.

### Legend

```
DIFF  = ittage_prm_tgt != ittage_alt_tgt (stored targets differ)
HIT   = ittage_hit (at least one tagged table hit)
UP    = ittage_using_primary
MISP  = indir_mispredict (from ittage_upd_inp_t, not pred_meta)
uWR   = useful write enable
uACT  = useful action (Inc/Dec u_eff)
uSEL  = useful component select
          PRM = ittage_prm_comp
          ALT = ittage_alt_comp
uIDX  = useful index select
          PRM = ittage_prm_idx
          ALT = ittage_alt_idx
uWD   = useful write data select
          PRM = ittage_prm_useful
          ALT = ittage_alt_useful
x     = don't care
-     = not applicable
```

### Table 7 - USEFUL modification truth table

| # | DIFF | HIT | UP | MISP | uWR | uACT | uSEL | uIDX | uWD |
|---|------|-----|----|------|-----|------|------|------|-----|
| 1 | 0    | x   | x  | x    | 0   | -    | x    | x    | x   |
| 2 | x    | 0   | x  | x    | 0   | -    | x    | x    | x   |
| 3 | 1    | 1   | 1  | 0    | 1   | INC  | PRM  | PRM  | PRM |
| 4 | 1    | 1   | 1  | 1    | 1   | DEC  | PRM  | PRM  | PRM |
| 5 | 1    | 1   | 0  | 0    | 1   | INC  | ALT  | ALT  | ALT |
| 6 | 1    | 1   | 0  | 1    | 1   | DEC  | ALT  | ALT  | ALT |

### Row suppression notes

Rows 1 and 2 both independently suppress the useful write
(uWR=0). They have no priority relationship between them.
If both conditions are true simultaneously (DIFF=0 and HIT=0)
the outcome is the same: uWR=0. No ordering is required and
no priority encoding should be inferred. Rows 3-6 are only
reachable when both row 1 and row 2 conditions are false
(DIFF=1 and HIT=1).

Row 1: predictions agreed -- primary and alternate stored
the same target. No useful information about relative
provider quality is available regardless of outcome.

Row 2: no tagged table hit. There is no entry to update.
HIT=0 with DIFF=1 is structurally impossible -- if no
table hit occurred then neither prm_tgt nor alt_tgt holds
a valid stored value and DIFF is a don't care. The uWR=0
outcome is the same.

