```
 FILE:    conflicts_001.md
 SOURCE:  ia_context/planning/arch/fe_theory_of_operation.md
 STATUS:  WORK LIST - internal inconsistency pass
 UPDATED: 2026-07-10
 CONTACT: Jeff Nye
```

# Internal Inconsistencies: fe_theory_of_operation.md

Statements within `fe_theory_of_operation.md` that contradict other
statements within the same document. No external file was consulted.
Line numbers are against the document as of 2026-07-10.

Items 1 through 4, 11, and 13 through 17 are resolvable from the
document alone. Items 5, 6, 8, 9, 10, and 12 require a decision.

---

## 1. Stage Assignment

```
  C-1  RAS stage.
       :52-53   predictor stage table assigns RAS to p2 only
       :87-91   section 2.2, RAS presents top-of-stack at p1
       :396-397 section 9, same

       The RAS is at p1 and p2, or the table is wrong.
       STATUS: open

  C-2  ITTAGE stage.
       :52-53   predictor stage table assigns ITTAGE to p2 only
       :42      stage list, "p3 SC final. ITTAGE final."
       :140     section 3.2 lists ITTAGE final as a p3 redirect source
       :179-180 section 3.3, ITTAGE final available at p3

       STATUS: open

  C-3  Metadata capture stage.
       :244     bp_ftq_meta_t captured at p2 for predictors that
                finalize at p2, "and at p3 for the SC"

       Per C-2 the ITTAGE also finalizes at p3. Either its metadata
       is captured at p2 in raw form, or the sentence is incomplete.
       STATUS: open
```

---

## 2. Prediction Path

```
  C-4  p1 mux table overlaps itself.
       :71-74   "LP output valid" selects the LP
                "otherwise" selects the uBTB
                "neither valid" selects PC + fetch_width

       The second row already consumed the third row's case. A uBTB
       miss satisfies both.
       STATUS: open

  C-5  br_type write time.                        NEEDS DECISION
       :99      fast-path entry written at p1
       :211     fast-path entry carries br_type
       :162     section 3.3, the FTB identifies branch type at p2
       :562     FE-U1, br_type does not exist until p2

       The document does not state what br_type holds between p1 and
       p2. The encoding does include none.
       STATUS: open, bears on FE-U1

  C-6  The RAS redirect.                          NEEDS DECISION
       :166     section 3.3, a p2 redirect selects RAS spec_pop_addr
                for a return
       :87-91   section 2.2, the RAS supplies that target at p1

       What the p2 RAS redirect corrects is not stated.
       STATUS: open, bears on FE-U1

  C-7  FE-2 is narrower than the body.
       :441-443 FE-2, initial prediction formed "by selection at p1
                between the LP and the uBTB"
       :74      section 2.1 adds the PC + fetch_width case
       :87-91   section 2.2 adds the RAS return target

       STATUS: open
```

---

## 3. Checkpoint and Restore

```
  C-8  Checkpoint storage.                        NEEDS DECISION
       :218-219 ghist_ptr and phist_ptr listed as fields of
                bp_ftq_entry_t
       :279-285 section 6.1, held as register arrays indexed by the
                FTQ entry index, "plus the RAS snapshot carried in
                the fast-path entry"

       The 6.1 phrasing reads as excluding them from the entry. They
       are in one place or the other.
       STATUS: open

  C-9  Checkpoint polarity.                       NEEDS DECISION
       :295     section 6.1, checkpoints written with post-update
                pointer values
       :110-111 section 2.3, the entry records "the architectural
                state the prediction was made against"

       Those are different values. Restoring post-update pointers on
       a redirect of that same entry restores state that includes the
       entry's own history write.
       STATUS: open

  C-10 Restore source.                            NEEDS DECISION
       :299     section 6.2 restores from "the checkpoint of the
                entry being corrected"
       :404     section 9 restores the RAS from "the snapshot of the
                last known-good entry"

       Same event, two different entries named.
       STATUS: open
```

---

## 4. Handshakes and Updates

```
  C-11 Two handshakes describe one crossing.
       :366     section 8 declares three handshakes
       :368-371 "Prediction issue": the uBTB holds its output stable
                when the FTQ cannot accept it
       :378-380 "Prediction delivery": consumer_ready and pred_rdy

       Both describe a prediction crossing into the FTQ, by different
       mechanisms. "Prediction issue" also names only the uBTB,
       though the p1 prediction may come from the LP.
       STATUS: open

  C-12 Arbitration stated after being scoped out. NEEDS DECISION
       :365     section 8 declares the RAM arbitration model out of
                scope
       :382-384 section 8 then states a grant-ordering rule
       :464-466 FE-9 restates it

       STATUS: open

  C-13 Update channel branch classes.
       :316     section 7.1, each channel "carries both conditional
                and indirect resolution"
       :326-330 section 7.2 fan-out covers four branch classes,
                including return and direct unconditional

       STATUS: open

  C-14 Stale redirects versus FE-5.
       :190     section 3.4, the FTQ tracks which redirects are stale
                and discards them
       :452-454 FE-5, no prediction and no update is dropped

       Separately: if the later stage always wins by stage order, a
       redirect for one entry index cannot arrive out of stage order.
       What a stale redirect is, is not stated.
       STATUS: open
```

---

## 5. Editorial

```
  C-15 File name.
       :2       header names the file tmp_004.md
       :602     history entry names tmp_004
       The file is fe_theory_of_operation.md.
       STATUS: open

  C-16 confidence width.
       :215     given as a literal 4 bits alongside FTQ_CONF_BITS
       :568-570 FE-U3 calls FTQ_CONF_BITS a placeholder
       STATUS: open

  C-17 Prediction slot count.
       :413     the count is parameterized as NUM_PRED_SLOTS
       :418     section 10 states "two prediction slots per fetch
                bundle" as fact
       STATUS: open
```

---

## 6. Document History

```
  2026-07-10  Created. Seventeen internal inconsistencies found in
              fe_theory_of_operation.md. Six are marked NEEDS
              DECISION; C-5 and C-6 bear on FE-U1.
```
