# tage_cntrl CTR Update Rules
```
 FILE:    tage_cntrl_ctr_update_rules.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-04
 CONTACT: Jeff Nye
```

---

## Notes

- prm_comp > 0  : primary provider is a tagged table (T1-T4)
- alt_comp > 0  : alternate provider is a tagged table (T1-T4)
- comp == 0     : T0 (BIM fallback)
- pred_diff     : tage_prm_tkn != tage_alt_tkn
- resolved_taken: supplied at update time via tage_upd_inp_t
- X             : don't care
- —             : no action
- -             : not applicable (one provider is T0)

---

## CTR Update Table

| #   | tage_using_primary | tage_pred_tkn | resolved_taken | pred_diff | tage_prm_comp | tage_alt_comp | Action(primary) | Action(alt) | Action(T0) | Explanation                                       |
|-----|--------------------|---------------|----------------|-----------|---------------|---------------|-----------------|-------------|------------|---------------------------------------------------|
| 1   | 1                  | 1             | 1              | X         | >0            | >0            | **INC**         | —           | —          | Provider = primary, predicted taken correctly     |
| 2   | 1                  | 0             | 0              | X         | >0            | >0            | **INC**         | —           | —          | Provider = primary, predicted not-taken correctly |
| 3   | 1                  | 1             | 0              | 1         | >0            | >0            | **DEC**         | **INC**     | —          | Provider = primary wrong, alt opposite prediction |
| 4   | 1                  | 0             | 1              | 1         | >0            | >0            | **DEC**         | **INC**     | —          | Provider = primary wrong, alt opposite prediction |
| 5   | 1                  | 1             | 0              | 0         | >0            | >0            | **DEC**         | —           | —          | Provider = primary wrong, alt same or ignored     |
| 6   | 1                  | 0             | 1              | 0         | >0            | >0            | **DEC**         | —           | —          | Provider = primary wrong, alt same or ignored     |
| 7   | 0                  | 1             | 1              | X         | >0            | >0            | —               | **INC**     | —          | Provider = alt, predicted taken correctly         |
| 8   | 0                  | 0             | 0              | X         | >0            | >0            | —               | **INC**     | —          | Provider = alt, predicted not-taken correctly     |
| 9   | 0                  | 1             | 0              | 1         | >0            | >0            | **INC**         | **DEC**     | —          | Provider = alt wrong, primary opposite prediction |
| 10  | 0                  | 0             | 1              | 1         | >0            | >0            | **INC**         | **DEC**     | —          | Provider = alt wrong, primary opposite prediction |
| 11  | 0                  | 1             | 0              | 0         | >0            | >0            | —               | **DEC**     | —          | Provider = alt wrong, pred_diff ignored           |
| 12  | 0                  | 0             | 1              | 0         | >0            | >0            | —               | **DEC**     | —          | Provider = alt wrong, pred_diff ignored           |
| 13a | X                  | 0             | 0              | X         | 0             | 0             | —               | —           | **INC**    | Provider = bim, bim was correct                   |
| 13b | X                  | 0             | 1              | X         | 0             | 0             | —               | —           | **DEC**    | Provider = bim, bim was wrong                     |
| 13c | X                  | 1             | 0              | X         | 0             | 0             | —               | —           | **DEC**    | Provider = bim, bim was wrong                     |
| 13d | X                  | 1             | 1              | X         | 0             | 0             | —               | —           | **INC**    | Provider = bim, bim was correct                   |
| 14  | 1                  | 1             | 0              | X         | >0            | 0             | **DEC**         | —           | -          | Alt invalid (BIM), provider = primary, wrong      |
| 15  | 1                  | 0             | 1              | X         | >0            | 0             | **DEC**         | —           | -          | Alt invalid (BIM), provider = primary, wrong      |
| 16  | 1                  | 1             | 1              | X         | >0            | 0             | **INC**         | —           | -          | Alt invalid (BIM), provider = primary, correct    |
| 17  | 1                  | 0             | 0              | X         | >0            | 0             | **INC**         | —           | -          | Alt invalid (BIM), provider = primary, correct    |
| 18  | x                  | x             | x              | X         | 0             | >0            | —               | —           | -          | Unreachable, invalid condition                    |

