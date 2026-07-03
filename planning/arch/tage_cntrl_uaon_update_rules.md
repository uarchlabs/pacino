<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# tage_cntrl UAON Update Rules
```
 FILE:    tage_tmp_uaon_update_rules.md
 SOURCE:  various
 STATUS:  DRAFT (proposed TD#87 reconciliation of
          tage_cntrl_uaon_update_rules.md)
 UPDATED: 2026-07-02
 CONTACT: Jeff Nye
```

Changelog:
- 2026-07-02 (TD#87): the UAON update gate now keys on tage_pred_weak,
  not tage_pred_strong. TD#87 redefined tage_pred_strong to mean
  STRICTLY strong (3'b000/3'b111), which is narrower than the prior
  "NOT WEAK" set. Gating on the new tage_pred_strong would wrongly act
  on medium CTRs. Behavior of the rule is unchanged from the original
  intent (act only on a weak/boundary prediction); only the gating
  signal and the doc terminology are corrected.

---

## USE_ALT_ON_NA (UAON) Background

Two USE_ALT_ON_NA (UAON) registers heuristically qualify the
selection of primary or alternative components during prediction.
During update the UAON registers are conditionally modified based
on the correctness of the predictions.

UAON has no impact when both the primary and alternative
components are tagged table misses (tage_prm_comp == 0 and
tage_alt_comp == 0). If TTM is asserted this section does
not apply.

---

## UAON Implementation

Two registers: uaon_0 and uaon_1, one per prediction slot.
Both are unsigned 4b saturating counters owned by tage_cntrl.
Both operate independently. No cross-slot interaction.

Parameter: TAGE_UAON_THRES = 8, defined in bp_defines_pkg.sv.

---

## Terminology

Primary component: the table with a tag hit and the longest
history length. tage_prm_comp holds its table index.

Alternative component: the table with the next lower history
length and a tag hit. tage_alt_comp holds its table index.

NOT WEAK: with a 3b CTR, weak states are 3'b011 and 3'b100
only. All other CTR values are NOT WEAK.

tage_pred_weak: set from the final provider CTR after the UAON
mux has selected primary or alternative. Asserted when that CTR
is 3'b011 or 3'b100. This is the UAON update gate.

tage_pred_strong: per TD#87, asserted only when the final
provider CTR is 3'b000 or 3'b111. NOTE: this is STRICTLY strong,
NOT the "NOT WEAK" set -- medium CTRs (001/010/101/110) have
tage_pred_strong=0 AND tage_pred_weak=0. Do not use
tage_pred_strong as the UAON gate; use tage_pred_weak.
See bp_structs_pkg.sv for field definitions.

---

## Component Selection During Prediction

Primary component CTR is available in tage_prm_ctr.

  if (tage_prm_ctr is NOT WEAK)
      select primary component
  else
      if (uaon_N >= TAGE_UAON_THRES)
          select alternative component
      else
          select primary component

NOT WEAK condition:
  not_weak = (tage_prm_ctr != 3'b011) && (tage_prm_ctr != 3'b100)

tage_using_primary reflects the result of this selection.
tage_pred_weak reflects the weak (boundary) condition on the
final provider CTR; tage_pred_strong reflects strictly
{3'b000, 3'b111} per TD#87.

---

## UAON Modification During Update

These rules apply independently to uaon_0 and uaon_1.

### Signal names

Full signal paths for reference:

  tage_pred_weak   = tage_upd_inp_u0[s].tage_pred_meta.tage_pred_weak
  cond_mispredict  = tage_upd_inp_u0[s].cond_mispredict
  tage_prm_tkn     = tage_upd_inp_u0[s].tage_pred_meta.tage_prm_tkn
  tage_alt_tkn     = tage_upd_inp_u0[s].tage_pred_meta.tage_alt_tkn

### Correctness definitions

TAGE predicts direction. Correctness is taken/not-taken match.

  prm_correct = (resolved_taken == tage_prm_tkn)
  prm_wrong   = (resolved_taken != tage_prm_tkn)
  alt_correct = (resolved_taken == tage_alt_tkn)
  alt_wrong   = (resolved_taken != tage_alt_tkn)

### Update rules

  if (!tage_pred_weak)
      -> do nothing        // provider was strong or medium
  else if (prm_wrong && alt_correct)
      -> increment uaon_N (saturate at 4b max)
  else if (prm_correct && alt_wrong)
      -> decrement uaon_N (saturate at 0)
  else
      -> do nothing        // weak but both-wrong or both-right

### Truth table

| tage_pred_weak | prm_wrong | alt_correct | prm_correct | alt_wrong | Action           |
|----------------|-----------|-------------|-------------|-----------|------------------|
| 0              | X         | X           | X           | X         | none (not weak)  |
| 1              | 1         | 1           | 0           | 0         | INC uaon_N       |
| 1              | 0         | 0           | 1           | 1         | DEC uaon_N       |
| 1              | 1         | 0           | 0           | 1         | none (both wrong)|
| 1              | 0         | 1           | 1           | 0         | none (both right)|
