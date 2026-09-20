<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# ittage_cntrl CTR Update Rules
```
 FILE:    ittage_cntrl_ctr_update_rules.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-09-20
 CONTACT: Jeff Nye
```

---

## Notes
- prm_comp > 0  : primary provider is a tagged table (IT1-IT5)
- alt_comp > 0  : alternate provider is a tagged table (IT1-IT5)
- comp == 0     : no hit. ITTAGE has no base table. When H=0
                  there is no entry to update and no CTR action
                  is taken for either provider.
- indir_mispredict: supplied at update time via ittage_upd_inp_t.
                  ITTAGE predicts target not direction. There is
                  no pred_diff in ITTAGE. See
                  ittage_cntrl_decisions.md CTR Update Rules.
- x             : don't care
- -             : not applicable
- --            : no action

---

## CTR Semantics
CTR is a confidence counter in ITTAGE, not a direction counter.
INC means increment toward max (higher confidence).
DEC means decrement toward zero (lower confidence).
CTR reaching null triggers target replacement on next
misprediction. See ittage_interfaces.md Target Write Gating;
allocation is a separate path, ittage_cntrl_alloc_rules.md.

The legend read PT as ittage_pred_target, a signal ittage_cntrl
does not produce, and pT / aT as ittage_prm_target /
ittage_alt_target, where the meta fields are _tgt. This section
pointed target replacement at the allocation rules. Session-072.

---

## CTR Update Table

This table is entered when pred_src == PRED_ITTAGE. The H column
gates all rows -- when H=0 no update is performed regardless of
any other signal state (row 1). Rows marked ASSERT are impossible
conditions enforced by ittage_assert.sv at simulation time.

Legend:
```
H     = ittage_hit
UP    = ittage_using_primary
PT    = VIRT_ittage_pred_tgt: ittage_prm_tgt when UP=1,
        ittage_alt_tgt when UP=0. Not a physical signal
        (ittage_interfaces.md Semantics); ittage_cntrl does
        not select a target (ittage_cntrl_decisions.md Final
        target).
RT    = resolved_target
pT    = ittage_prm_tgt
aT    = ittage_alt_tgt
MIS   = indir_mispredict, supplied in ittage_upd_inp_t. It
        equals (PT != RT); the table is not evaluated by
        comparing targets.
pCMP  = ittage_prm_comp
aCMP  = ittage_alt_comp
pACT  = action for primary CTR
aACT  = action for alternate CTR
x     = don't care
--    = no action
A, B  = distinct target address values (abstractions)
```

```
if PT == RT then MIS = 0 (correct prediction)
if PT != RT then MIS = 1 (misprediction)

When UP=0: alt is provider. pT and pCMP are don't care
           for CTR update purposes. Rows retain explicit
           pT and pCMP values for test coverage -- each
           row maps to one test case in tb_ittage.sv.

When UP=1: primary is provider. aT and aCMP are don't care
           for CTR update purposes. Same test coverage
           rationale applies.

UP=0 with pCMP=0 (rows 2, 4, 6, 8, 10, 12, 14, 16) cannot
arise from a prediction: the alternate is found only below a
primary, and UP=0 requires a null primary
(ittage_cntrl_decisions.md). Those rows are update inputs a
test can present, with pCMP don't-care; they are not reachable
states. Session-071.
```

| #  | H | UP | PT | RT | MIS | pT | aT | pCMP | aCMP | pACT  | aACT  | Explanation                              |
|----|---|----|----|----|-----|----|----|------|------|-------|-------|------------------------------------------|
|  1 | 0 | x  | x  | x  | x   | x  | x  | x    | x    | --    | --    | No hit, no update                        |
|  2 | 1 | 0  | A  | A  | 0   | A  | A  | =0   | >0   | --    | INC   | UP=0, correct, pT=A aT=A pCMP=0          |
|  3 | 1 | 0  | A  | A  | 0   | A  | A  | >0   | >0   | --    | INC   | UP=0, correct, pT=A aT=A pCMP>0          |
|  4 | 1 | 0  | A  | A  | 0   | B  | A  | =0   | >0   | --    | INC   | UP=0, correct, pT=B aT=A pCMP=0          |
|  5 | 1 | 0  | A  | A  | 0   | B  | A  | >0   | >0   | --    | INC   | UP=0, correct, pT=B aT=A pCMP>0          |
|  6 | 1 | 0  | A  | B  | 1   | A  | A  | =0   | >0   | --    | DEC   | UP=0, mispredict, pT=A aT=A pCMP=0       |
|  7 | 1 | 0  | A  | B  | 1   | A  | A  | >0   | >0   | --    | DEC   | UP=0, mispredict, pT=A aT=A pCMP>0       |
|  8 | 1 | 0  | A  | B  | 1   | B  | A  | =0   | >0   | --    | DEC   | UP=0, mispredict, pT=B aT=A pCMP=0       |
|  9 | 1 | 0  | A  | B  | 1   | B  | A  | >0   | >0   | --    | DEC   | UP=0, mispredict, pT=B aT=A pCMP>0       |
| 10 | 1 | 0  | B  | A  | 1   | A  | B  | =0   | >0   | --    | DEC   | UP=0, mispredict, pT=A aT=B pCMP=0       |
| 11 | 1 | 0  | B  | A  | 1   | A  | B  | >0   | >0   | --    | DEC   | UP=0, mispredict, pT=A aT=B pCMP>0       |
| 12 | 1 | 0  | B  | A  | 1   | B  | B  | =0   | >0   | --    | DEC   | UP=0, mispredict, pT=B aT=B pCMP=0       |
| 13 | 1 | 0  | B  | A  | 1   | B  | B  | >0   | >0   | --    | DEC   | UP=0, mispredict, pT=B aT=B pCMP>0       |
| 14 | 1 | 0  | B  | B  | 0   | A  | B  | =0   | >0   | --    | INC   | UP=0, correct, pT=A aT=B pCMP=0          |
| 15 | 1 | 0  | B  | B  | 0   | A  | B  | >0   | >0   | --    | INC   | UP=0, correct, pT=A aT=B pCMP>0          |
| 16 | 1 | 0  | B  | B  | 0   | B  | B  | =0   | >0   | --    | INC   | UP=0, correct, pT=B aT=B pCMP=0          |
| 17 | 1 | 0  | B  | B  | 0   | B  | B  | >0   | >0   | --    | INC   | UP=0, correct, pT=B aT=B pCMP>0          |
| 18 | 1 | 1  | A  | A  | 0   | A  | A  | >0   | =0   | INC   | --    | UP=1, correct, aT=A aCMP=0               |
| 19 | 1 | 1  | A  | A  | 0   | A  | A  | >0   | >0   | INC   | --    | UP=1, correct, aT=A aCMP>0               |
| 20 | 1 | 1  | A  | A  | 0   | A  | B  | >0   | =0   | INC   | --    | UP=1, correct, aT=B aCMP=0               |
| 21 | 1 | 1  | A  | A  | 0   | A  | B  | >0   | >0   | INC   | --    | UP=1, correct, aT=B aCMP>0               |
| 22 | 1 | 1  | A  | B  | 1   | A  | A  | >0   | =0   | DEC   | --    | UP=1, mispredict, aT=A aCMP=0            |
| 23 | 1 | 1  | A  | B  | 1   | A  | A  | >0   | >0   | DEC   | --    | UP=1, mispredict, aT=A aCMP>0            |
| 24 | 1 | 1  | A  | B  | 1   | A  | B  | >0   | =0   | DEC   | --    | UP=1, mispredict, aT=B aCMP=0            |
| 25 | 1 | 1  | A  | B  | 1   | A  | B  | >0   | >0   | DEC   | --    | UP=1, mispredict, aT=B aCMP>0            |
| 26 | 1 | 1  | B  | A  | 1   | B  | A  | >0   | =0   | DEC   | --    | UP=1, mispredict, aT=A aCMP=0            |
| 27 | 1 | 1  | B  | A  | 1   | B  | A  | >0   | >0   | DEC   | --    | UP=1, mispredict, aT=A aCMP>0            |
| 28 | 1 | 1  | B  | A  | 1   | B  | B  | >0   | =0   | DEC   | --    | UP=1, mispredict, aT=B aCMP=0            |
| 29 | 1 | 1  | B  | A  | 1   | B  | B  | >0   | >0   | DEC   | --    | UP=1, mispredict, aT=B aCMP>0            |
| 30 | 1 | 1  | B  | B  | 0   | B  | A  | >0   | =0   | INC   | --    | UP=1, correct, aT=A aCMP=0               |
| 31 | 1 | 1  | B  | B  | 0   | B  | A  | >0   | >0   | INC   | --    | UP=1, correct, aT=A aCMP>0               |
| 32 | 1 | 1  | B  | B  | 0   | B  | B  | >0   | =0   | INC   | --    | UP=1, correct, aT=B aCMP=0               |
| 33 | 1 | 1  | B  | B  | 0   | B  | B  | >0   | >0   | INC   | --    | UP=1, correct, aT=B aCMP>0               |
| A1 | 1 | x  | x  | x  | x   | x  | x  | =0   | =0   | ASSERT| ASSERT| Invalid: H=1 pCMP=0 aCMP=0.              |
|    |   |    |    |    |     |    |    |      |      |       |       | ittage_assert.sv assertion 1.            |
| A2 | 1 | 1  | x  | x  | x   | x  | x  | =0   | x    | ASSERT| ASSERT| Invalid: UP=1 pCMP=0.                    |
|    |   |    |    |    |     |    |    |      |      |       |       | ittage_assert.sv assertion 2.            |
| A3 | 1 | 0  | x  | x  | x   | x  | x  | x    | =0   | ASSERT| ASSERT| Invalid: UP=0 H=1 aCMP=0.                |
|    |   |    |    |    |     |    |    |      |      |       |       | ittage_assert.sv assertion 3.            |

