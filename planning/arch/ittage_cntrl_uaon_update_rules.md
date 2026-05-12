# ittage_cntrl UAON Update Rules
```
 FILE:    ittage_cntrl_uaon_update_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-29
 CONTACT: Jeff Nye
```

---

## USE_ALT_ON_NA (UAON) Background

In TAGE like predictors, including Indirect Target TAGE (ITTAGE)
a set of register(s) is used to possibly prefer the alternative
component's predictions over the primary component's prediction.

USE_ALT_ON_NA (Use Alternate Prediction on Newly Allocated, aka
UAON) controls what happens when a tagged component provides a
prediction from a newly allocated entry -- one that hasn't yet
been trained and therefore has a null confidence counter.

Specifically, when the matching tagged component's CTR is null
(3'b000 -- no confidence, target replacement candidate), the
predictor must decide:

- Use the tagged component's prediction anyway, or
- Fall back to the alternate (next-longest-history) prediction

USE_ALT_ON_NA is a small saturating counter that tracks whether
trusting newly allocated entries or deferring to the alternate
has been more accurate recently. If it is biased toward "use
alternate," the predictor ignores null-CTR entries and falls
back; if biased toward "use new," it trusts them immediately.

This design implements two USE_ALT_ON_NA (UAON) registers to
heuristically qualify the selection of primary or alternative
components during prediction. During update the UAON registers
are conditionally modified based on the correctness of the
predictions.

UAON has no impact when the tagged tables have missed.
If ittage_hit == 0 this section does not apply.

---

## UAON Implementation

Two registers: uaon_0 and uaon_1, one per prediction slot.
Both are unsigned 4b saturating counters owned by ittage_cntrl.
Both operate independently. No cross-slot interaction.

Parameter: IT_UAON_THRES = 8, defined in bp_defines_pkg.sv.

---

## Terminology

Primary component: the table with a tag hit and the longest
history length. ittage_prm_comp holds its table index.

Alternative component: the table with the next lower history
length and a tag hit. ittage_alt_comp holds its table index.

NOT NULL: CTR is not null when ittage_prm_ctr != 3'b000.
Null state is 3'b000 only -- the newly allocated, zero
confidence state. All other CTR values are NOT NULL.

ittage_pred_strong: set when the final provider CTR is NOT
NULL after the UAON mux has selected primary or alternative.
Reflects the NOT NULL condition on whichever component
actually supplied the prediction.
See bp_structs_pkg.sv for field definition.

---

## Component Selection During Prediction

Primary component CTR is available in ittage_prm_ctr.

```
if (ittage_prm_ctr != 3'b000)
    select primary component
else
    if (uaon_N >= IT_UAON_THRES)
        select alternative component
    else
        select primary component
```

NOT NULL condition:
```
not_null = (ittage_prm_ctr != 3'b000)
```

ittage_using_primary reflects the result of this selection.
ittage_pred_strong reflects NOT NULL on the final provider CTR.

---

## UAON Modification During Update

These rules apply independently to uaon_0 and uaon_1.

### Signal names

Full signal paths for reference:
```
ittage_pred_strong   = ittage_upd_inp_u0[s].ittage_pred_meta.ittage_pred_strong
ittage_prm_tgt       = ittage_upd_inp_u0[s].ittage_pred_meta.ittage_prm_tgt
ittage_alt_tgt       = ittage_upd_inp_u0[s].ittage_pred_meta.ittage_alt_tgt
indir_mispredict     = ittage_upd_inp_u0[s].indir_mispredict
resolved_target      = ittage_upd_inp_u0[s].resolved_target
```

### Correctness definitions

ITTAGE predicts target address. Correctness is target match.
```
prm_correct = (resolved_target == ittage_prm_tgt)
prm_wrong   = (resolved_target != ittage_prm_tgt)
alt_correct = (resolved_target == ittage_alt_tgt)
alt_wrong   = (resolved_target != ittage_alt_tgt)
```

### Update rules
```
if (ittage_pred_strong)
    -> do nothing
else if (prm_wrong && alt_correct)
    -> increment uaon_N (saturate at 4b max)
else if (prm_correct && alt_wrong)
    -> decrement uaon_N (saturate at 0)
else
    -> do nothing
```

### Truth table

| ittage_pred_strong | prm_wrong | alt_correct | prm_correct | alt_wrong | Action            |
|--------------------|-----------|-------------|-------------|-----------|-------------------|
| 1                  | X         | X           | X           | X         | none              |
| 0                  | 1         | 1           | 0           | 0         | INC uaon_N        |
| 0                  | 0         | 0           | 1           | 1         | DEC uaon_N        |
| 0                  | 1         | 0           | 0           | 1         | none (both wrong) |
| 0                  | 0         | 1           | 1           | 0         | none (both right) |

