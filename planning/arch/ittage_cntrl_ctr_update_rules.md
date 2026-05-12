# ittage_cntrl CTR Update Rules
```
 FILE:    ittage_cntrl_ctr_update_rules.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-04-29
 CONTACT: Jeff Nye
```

---

## Notes
- prm_comp > 0  : primary provider is a tagged table (IT1-IT5)
- alt_comp > 0  : alternate provider is a tagged table (IT1-IT5)
- comp == 0     : no hit (IT0 placeholder -- no base table in
                  ITTAGE)
- indir_mispredict: supplied at update time via ittage_upd_inp_t.
                  ITTAGE predicts target not direction. There is
                  no pred_diff in ITTAGE. See
                  ittage_cntrl_decisions.md CTR Update Rules.
- X             : don't care
- -             : not applicable
- --            : no action

---

## CTR Semantics
CTR is a confidence counter in ITTAGE, not a direction counter.
INC means increment toward max (higher confidence).
DEC means decrement toward zero (lower confidence).
CTR reaching null triggers target replacement on next
misprediction. See ittage_cntrl_alloc_rules.md.

---

## CTR Update Table
V = pred_src = PRED_ITTAGE && no_tagged_hit == 0
(at least one table hit)

| #  | V | using_primary | indir_mispredict | prm_comp | alt_comp | Action(prm) | Action(alt) | Explanation     |
|----|---|---------------|------------------|----------|----------|-------------|-------------|-----------------|
| 1  | 0 | x             | x                | x        | x        | --          | --          | No CTR updates  |
| 2  | 1 | 1             | 0                | x        | =0       | --          | --          | No CTR updates  |
| 3  | 1 | 1             | 0                | x        | >0       | --          | **INC**     | Inc Alternative |
| 4  | 1 | 1             | 1                | x        | =0       | --          | --          | No CTR updates  |
| 5  | 1 | 1             | 1                | x        | >0       | --          | **DEC**     | Dec Alternative |
| 6  | 1 | 0             | 0                | =0       | x        | --          | --          | No CTR updates  |
| 7  | 1 | 0             | 0                | >0       | x        | **INC**     | --          | Inc Primary     |
| 8  | 1 | 0             | 1                | =0       | x        | --          | --          | No CTR updates  |
| 9  | 1 | 0             | 1                | >0       | x        | **DEC**     | --          | Dec Primary     |

