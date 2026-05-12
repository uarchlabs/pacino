# tage_cntrl USEFUL Update Rules
```
 FILE:    tage_cntrl_use_update_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-29
 CONTACT: Jeff Nye
```

---

### Background

Each tagged TAGE table entry (T1-T4) contains a 2-bit USEFUL counter
field. The USEFUL field records whether an entry has recently provided
a correct prediction that disagreed with the alternative provider. An
entry with a non-zero USEFUL value has demonstrated recent predictive
value and is protected from eviction during allocation. An entry whose
USEFUL value has decayed to zero is a candidate for replacement. The
epoch-based aging mechanism described below allows this protection to
decay over time without requiring explicit per-entry writes: as the
lcl_epoch counter advances, the effective USEFUL value (u_eff) seen by
the allocation logic decreases for entries that have not been recently
updated, making them eligible for eviction even if their raw USEFUL
field is non-zero. USEFUL is updated only when the primary and alternate
providers disagree -- when they agree, no information about relative
provider quality is available and no update is performed.

---

### TAGE USEFUL Counter Aging
The TAGE predictor periodically ages the USEFUL counters in table
entries. Useful aging gradually removes replacement protection from
predictor entries that have not recently demonstrated value, allowing
stale entries to be evicted (allocated) in favor of new ones without
explicitly clearing the tables.

Aging is a two-phase process that fits within the existing prediction
request/update request process. During prediction requests, the EFFECTIVE
useful bits are used to determine which entry across the tables is the
target for replacement/allocation. The "EFFECTIVE useful bits" are the
aged view of the USEFUL bits across the entries.

The EFFECTIVE USEFUL values are returned in the prediction response and
used in the subsequent update phase.

There is an enable bit, tage_enable_aging, as a primary input to tage and tage_cntrl

There is a 32b bus that supplies the aging interval 
as a primary input to tage and tage_cntrl. called tage_aging_interval

There are two local 32b register in tage_ctnrl that holds the running interval count
called lcl_aging_interval_0 and lcl_aging_interval_1, each register serves the two prediction requests.

There are local 2b  registers in tage_ctnrl that holds the running epoch count
called lcl_epoch_0 and lcl_epoch_1. each register serves the two prediction requests

### TAGE Aging Epoch and Interval Operation

With TAGE aging enabled:

On the rising edge of reset lcl_aging_interval_0 and lcl_aging_interval_1 are 
loaded with the current value of tage_aging_interval

lcl_aging_interval_0 is a down counter which decrements for each assertion of tage_pred_rdy_0_p2 

lcl_aging_interval_1 is a down counter which decrements for each assertion of tage_pred_rdy_1_p2 

when lcl_aging_interval_0 reaches zero lcl_epoch_0 is incremented and
lcl_aging_interval_0 is loaded with the current value of tage_aging_interval

when lcl_aging_interval_1 reaches zero lcl_epoch_1 is incremented and
lcl_aging_interval_1 is loaded with the current value of tage_aging_interval

The value of the respective lcl_epoch_0/1 determines how a given entry's 
USEFUL counter is interpreted during prediction, allocation and updates.
USEFUL counter updates are described in the next section.

### TAGE USEFUL Counter Updates

#### Signals
The signals are found in the tage_pred_meta entry within tage_upd_inp_t,
with the exception of cond_mispredict which is found in tage_upd_inp_t.

The truth table for USEFUL counter updates is shown in Table 7.

#### Columns

The signals referenced are presumed to have tage_upd_inp.tage_pred_meta
prefixed, prefix was removed in the column header to limit table column width.

-   Preds differed (tage_prm_tkn != tage_alt_tkn)
    -   primary and alternative predictions differed

-   TTM (tagged table miss) (tage_prm_comp == 0 and tage_alt_comp == 0)
    -   Both the primary component and the alternative component were 0

-   Using primary (tage_using_primary)
    -   Primary component supplied the prediction, else alternative supplied

-   Mispredict (cond_mispredict)
    -   The provider's prediction was not correct

-   Useful WR, output
    -   The useful write signal to RAM
    -   This is an output of the table

-   Useful SEL, output
    -   The component selected for useful update
    -   Select either tage_prm_comp or tage_alt_comp
    -   This is an output of the table

-   Useful IDX, output
    -   The index into the component for useful update
    -   Select either tage_prm_idx or tage_alt_idx
    -   This is an output of the table

-   Useful WD, output
    -   Source provided to the saturating counter for increment or decrement
    -   Select either tage_prm_useful or tage_alt_useful
    -   This is an output of the table

-   Useful Action, output
    -   Increment or decrement of the effective useful value.
    -   Control flag to the effective useful add/sub. 
    -   See epoch aging description below


#### Table 7 - USEFUL modification truth table
|---|-----------|-------|-----------|------------|-----------|--------------|---------------|-----------------|-----------------| 
| # |Preds diff | TTM   | Using prm | Mispredict | Useful WR | Useful Action| Useful SEL    |   Useful IDX    |  Useful WD      |
|---|-----------|-------|-----------|------------|-----------|--------------|---------------|-----------------|-----------------|
| 1 |0          |  x    |     x     | x          | 0         | x            | x             | x               | x               |
| 2 |x          |  1    |     x     | x          | 0         | x            | x             | x               | x               |
| 3 |1          |  0    |     1     | 0          | 1         | Inc u_eff    | tage_prm_comp | tage_prm_idx    | tage_prm_useful |
| 4 |1          |  0    |     1     | 1          | 1         | Dec u_eff    | tage_prm_comp | tage_prm_idx    | tage_prm_useful |
| 5 |1          |  0    |     0     | 0          | 1         | Inc u_eff    | tage_alt_comp | tage_alt_idx    | tage_alt_useful |
| 6 |1          |  0    |     0     | 1          | 1         | Dec u_eff    | tage_alt_comp | tage_alt_idx    | tage_alt_useful |

Row 2 is also an invalid case, with tagged table miss preds diff is a don't care

Operations are performed on the effective version of the USEFUL bits. In
the table u_eff is the EFFECTIVE USEFUL value. The operations are
saturating on the 2bit range.

The formula below uses these terms:

-   u_eff is the calculated effective USEFUL value
-   USEFUL is the current raw value of the entry's useful field
-   EPOCH is the value in the entry's epoch field
-   TG_AGE_EPOCH is the value of either lcl_epoch_0 or lcl_epoch_1 epoch registers

> age = (TG_AGE_EPOCH -- EPOCH) mod 4
>
> if(age == 0) u_eff = USEFUL;
> if(age == 1) u_eff = USEFUL >> 1;
> else u_eff = 0;

On a prediction request the u_eff values for the primary and alternative
components are calculated. The provider component's MODIFIED u_eff is
returned in the prediction response. On the subsequent update these
values are written to either the primary or alternative entries
depending on the state of bpc_upd_data_t.common.using_primary. The
current value of the lcl_epoch_0/lcl_epoch_1 is written to the EPC 
field of the entry as well.

Theory:

Since the lcl_epoch_0/1 register is used to form the EFFECTIVE
USEFUL value the simple action of incrementing the TG_AGE_EPOCH
effectively ages all entries in all tables without the need to
update each entry individually.

