# ittage_cntrl Useful Counter Update Rules
```
 FILE:    ittage_cntrl_use_update_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-27
 CONTACT: Jeff Nye
```

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
replacement/allocation. The "EFFECTIVE useful bits" are the
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

## Effective Useful Computation

At predict time, ittage_cntrl computes u_eff for the primary
and alternative components using the slot's lcl_epoch register.

  age = (IT_AGE_EPOCH - EPOCH) mod 4

  if (age == 0) u_eff = USEFUL
  if (age == 1) u_eff = USEFUL >> 1
  else          u_eff = 0

Where:
  IT_AGE_EPOCH = lcl_epoch_0 or lcl_epoch_1 for the slot
  EPOCH        = EPC field of the RAM entry
  USEFUL       = USE field of the RAM entry

u_eff is a 2b saturating value.

The provider component's modified u_eff is returned in the
prediction response (ittage_pred_meta) on ittage_prm_useful
and ittage_alt_useful.

On the subsequent update, u_eff is written back to 
the USEFUL field of the entry. 

Since u_eff has already been provided during the
prediction response, during update the values in 
each slots update data
ittage_upd_inp[0/1].ittage_pred_meta.ittage_prm_useful or
ittage_upd_inp[0/1].ittage_pred_meta.ittage_alt_useful 
are written to the entry. Which value, prm or alt is
shown in the table.

The current lcl_epoch value is written to the EPC
field of the entry at the same time.

---

## Useful Counter Update -- Table 7

Signals below are prefixed by:
  ittage_upd_inp_u0[s].ittage_pred_meta

Prefix removed from column headers for brevity.

V   = pred_src == PRED_ITTAGE
NTH = no_tagged_hit (NTH==0 means at least 1 table hit)
TD  = ittage_pred_tgt != ittage_alt_tgt (tgt's differed)

| # | V | NTH | TD | Using prm | Mispredict | Useful WR | Useful Action | Useful SEL      | Useful IDX      | Useful WD         |
|---|---|-----|----|-----------|------------|-----------|---------------|-----------------|-----------------|-------------------|
| 1 | 0 | x   | x  | x         | x          | 0         | x             | x               | x               | x                 |
| 2 | 1 | 1   | x  | x         | x          | 0         | x             | x               | x               | x                 |
| 3 | 1 | 0   | 0  | x         | x          | 0         | x             | x               | x               | x                 |
| 4 | 1 | 0   | 1  | 1         | 0          | 1         | Inc u_eff     | ittage_prm_comp | ittage_prm_idx  | ittage_prm_useful |
| 5 | 1 | 0   | 1  | 1         | 1          | 1         | Dec u_eff     | ittage_prm_comp | ittage_prm_idx  | ittage_prm_useful |
| 6 | 1 | 0   | 1  | 0         | 0          | 1         | Inc u_eff     | ittage_alt_comp | ittage_alt_idx  | ittage_alt_useful |
| 7 | 1 | 0   | 1  | 0         | 1          | 1         | Dec u_eff     | ittage_alt_comp | ittage_alt_idx  | ittage_alt_useful |

### Column definitions

V            : pred_src == PRED_ITTAGE
NTH          : no_tagged_hit -- all IT1-IT5 tables missed
             : or !ittage_hit
TD           : ittage_pred_tgt != ittage_alt_tgt
               (primary and alternate predicted different targets)
Using prm    : ittage_using_primary
Mispredict   : indir_mispredict (from ittage_upd_inp_t, not meta)
Useful WR    : write enable output to RAM
Useful Action: Inc u_eff or Dec u_eff, saturating on 2b range
Useful SEL   : component selected for useful update
Useful IDX   : index into component for useful update
Useful WD    : source value for saturating inc/dec

### Notes

- Operations are performed on u_eff, not raw USEFUL.
- u_eff written back as USEFUL field in RAM entry.
- lcl_epoch written to EPC field on every useful update.
- Row 1: pred_src is not PRED_ITTAGE -- not an ITTAGE prediction.
- Row 2: no_tagged_hit -- no tagged table entry to update.
- Row 3: primary and alternate predicted the same target --
  no useful information gained regardless of outcome.
