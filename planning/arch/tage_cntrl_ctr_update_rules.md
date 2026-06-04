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

Legend:

UP    = `tage_using_primary`
PT    = `tage_pred_tkn`
RT    = `resolved_taken`
pT    = `tage_prm_taken`
aT    = `tage_alt_taken`
pCMP  = `tage_prm_comp`
aCMP  = `tage_alt_comp`
pACT  =  action for primary CTR
aACT  =  action for alternative CTR
t0ACT =  action for T0 (bim) CTR

```
diff  = `tage_prm_taken` != `tage_alt_taken`
         diff is for reference, diff is not a signal 
         in the prediction meta data
```

| #     | UP | PT | RT | diff | pT | aT | pCMP | aCMP | pACT | aACT | t0ACT | Explanation                                       |
|-------|----|----|----|------|----|----|------|------|------|------|-------|---------------------------------------------------|
| 1.1   | 1  | 1  | 1  | 1    | 1  | 0  | >0   | >0   | INC  | —    | —     | Provider = primary, predicted taken correctly     |
| 1.2   | 1  | 1  | 1  | 0    | 1  | 1  | >0   | >0   | INC  | —    | —     | Provider = primary, predicted taken correctly     |
| 2.1   | 1  | 0  | 0  | 0    | 0  | 0  | >0   | >0   | INC  | —    | —     | Provider = primary, predicted not-taken correctly |
| 2.2   | 1  | 0  | 0  | 1    | 0  | 1  | >0   | >0   | INC  | —    | —     | Provider = primary, predicted not-taken correctly |
| 3     | 1  | 1  | 0  | 1    | 1  | 0  | >0   | >0   | DEC  | INC  | —     | Provider = primary wrong, alt opposite prediction |
| 4     | 1  | 0  | 1  | 1    | 0  | 1  | >0   | >0   | DEC  | INC  | —     | Provider = primary wrong, alt opposite prediction |
| 5     | 1  | 1  | 0  | 0    | 1  | 1  | >0   | >0   | DEC  | —    | —     | Provider = primary wrong, alt same or ignored     |
| 6     | 1  | 0  | 1  | 0    | 0  | 0  | >0   | >0   | DEC  | —    | —     | Provider = primary wrong, alt same or ignored     |
| 7.1   | 0  | 1  | 1  | 1    | 0  | 1  | >0   | >0   | —    | INC  | —     | Provider = alt, predicted taken correctly         |
| 7.2   | 0  | 1  | 1  | 0    | 1  | 1  | >0   | >0   | —    | INC  | —     | Provider = alt, predicted taken correctly         |
| 8.1   | 0  | 0  | 0  | 0    | 0  | 0  | >0   | >0   | —    | INC  | —     | Provider = alt, predicted not-taken correctly     |
| 8.2   | 0  | 0  | 0  | 1    | 1  | 0  | >0   | >0   | —    | INC  | —     | Provider = alt, predicted not-taken correctly     |
| 9     | 0  | 1  | 0  | 1    | 0  | 1  | >0   | >0   | INC  | DEC  | —     | Provider = alt wrong, primary opposite prediction |
| 10    | 0  | 0  | 1  | 1    | 1  | 0  | >0   | >0   | INC  | DEC  | —     | Provider = alt wrong, primary opposite prediction |
| 11    | 0  | 1  | 0  | 0    | 1  | 1  | >0   | >0   | —    | DEC  | —     | Provider = alt wrong, pred_diff ignored           |
| 12    | 0  | 0  | 1  | 0    | 0  | 0  | >0   | >0   | —    | DEC  | —     | Provider = alt wrong, pred_diff ignored           |
| 13a   | 1  | 0  | 0  | 0    | 0  | 0  | 0    | 0    | —    | —    | DEC   | BIM predicted NT, resolved NT, correct |
| 13b   | 1  | 0  | 1  | 0    | 0  | 0  | 0    | 0    | —    | —    | INC   | BIM predicted NT, resolved T, wrong |
| 13c   | 1  | 1  | 0  | 0    | 1  | 1  | 0    | 0    | —    | —    | DEC   | BIM predicted T, resolved NT, wrong |
| 13d   | 1  | 1  | 1  | 0    | 1  | 1  | 0    | 0    | —    | —    | INC   | BIM predicted T, resolved T, correct |
| 13e   | 0  | x  | x  | x    | x  | x  | 0    | 0    |ASSERT|ASSERT|ASSERT | Invalid: UP=0 when pCMP=aCMP=0. ADR-001 violation. tage_assert.sv fires. No RTL action. |
| 14.1  | 1  | 1  | 0  | 0    | 1  | 1  | >0   | 0    | DEC  | —    | -     | Alt=BIM, primary wrong, alt same |
| 14.2  | 1  | 1  | 0  | 1    | 1  | 0  | >0   | 0    | DEC  | —    | -     | Alt=BIM, primary wrong, alt opposite |       
| 15.1  | 1  | 0  | 1  | 0    | 0  | 0  | >0   | 0    | DEC  | —    | -     | Alt=BIM, primary predicted NT, resolved T, wrong |
| 15.2  | 1  | 0  | 1  | 1    | 0  | 1  | >0   | 0    | DEC  | —    | -     | Alt=BIM, primary predicted NT, resolved T, wrong, alt opposite |
| 16.1  | 1  | 1  | 1  | 0    | 1  | 1  | >0   | 0    | INC  | —    | -     | Alt=BIM, primary predicted T, resolved T, correct, alt same |
| 16.2  | 1  | 1  | 1  | 1    | 1  | 0  | >0   | 0    | INC  | —    | -     | Alt=BIM, primary predicted T, resolved T, correct, alt opposite |
| 17.1  | 1  | 0  | 0  | 0    | 0  | 0  | >0   | 0    | INC  | —    | -     | Alt=BIM, primary predicted NT, resolved NT, correct, alt same |
| 17.2  | 1  | 0  | 0  | 1    | 0  | 1  | >0   | 0    | INC  | —    | -     | Alt=BIM, primary predicted NT, resolved NT, correct, alt opposite |
| 18    | x  | x  | x  | x    | x  | x  | 0    | >0   |ASSERT|ASSERT|ASSERT | invalid condition pCMP=0 aCMP>0, handled by assert|


## ADR

### ADR-001

ADR: tage_using_primary when BIM is sole provider

When tage_prm_comp=0 and tage_alt_comp=0 at prediction
time, tage_using_primary shall be 1.

Rationale: when no tagged table hits, BIM is the sole
provider. The concept of primary vs alternate does not
apply. BIM is defined as the primary provider in this
case. using_primary=0 would be architecturally
meaningless and is disallowed.

RTL: tage_cntrl.sv pred_logic block sets using_prm_p1
to 1'b1 by default. The UAON override that sets it to
0 is gated on prm_comp != 0 and therefore cannot fire
in the BIM case.

Enforcement: tage_assert.sv assertion on tage_pred_rdy_p2 and tage_upd_val_u0.

Status: ACTIVE. RTL verified. Assertion implemented.
