```
 FILE:    cold_start.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-07-08
 CONTACT: Jeff Nye
```

# Intro

Contains a description of the front as it exits reset. This
likely duplicates information found in fe.md. This document
ultimately will contain the final description and the fe.md 
document will point to this document.

This document has xianshan specific references.

There is another version of this document called c.md, which is 
being delveloped in parallel specific to the intended pacino behavior.

In the final version of this document the pacino specific theory of
operation will be described. That will require merging the section
in fe.md, this document and c.md. Again cold_start.md is the intended
final document containing theory of operation of the frontend from
reset to steady state.


# Cold start: FTB miss behavior

Front-end behavior after reset, with an empty FTB. Scope: conditional
branches (BEQ, BNE, BLT, ...).

1. Reset. `s0_pc` is set to the reset vector (e.g. 0x80000000 or the
   ISA-defined equivalent).

2. The BPU looks up `s0_pc` in the FTB. The FTB is empty, so the lookup
   returns `hit = false`. No FTB entry exists for this block.

3. On `hit = false` the BPU predicts fall-through:
   - `br_taken_mask` = all zeros
   - predicted next PC = `pc + FetchWidth*4`
     (`FullBranchPrediction.allTarget`, not-hit case)
   - `cfiIndex.valid` = false

4. `s0_pc` advances to the fall-through address each cycle. The lookup
   misses again and returns fall-through again. The BPU walks sequential
   addresses while the FTB misses. These predictions enter the FTQ and
   are sent to the IFU.

5. The IFU fetches the block and predecodes it. For a conditional
   branch:
   - Predecode result: the branch exists at offset K, and its target is
     `PC + immediate` (direct branch). Predecode does not resolve
     direction.
   - Direction source: a conditional branch outcome depends on register
     values evaluated at execute. Direction is resolved in the backend,
     not at predecode.
   - Resolved taken: the fall-through path executes speculatively. The
     backend resolves the branch taken and detects the mispredict. The
     backend issues `redirect` with the taken outcome and target;
     `redirctFromIFU` = false. The front end flushes the wrong-path
     fetches and sets `s0_pc` to the resolved target. Correction occurs
     at execute.
   - Resolved not-taken: fall-through matches the resolved direction. No
     redirect is issued.
   - FTB update: the predecode result (`pdWb`) is sent to the FTQ.
     `FTBEntryGen` builds an FTB entry (branch at offset K, target) and
     writes it via `update`. The FTB entry records branch presence and
     target, not direction. The direction predictor (TAGE/SC) is trained
     by backend commit.

6. On the next prediction of this PC the FTB returns `hit = true`, with
   the branch at offset K and its target. Direction is supplied by the
   directional predictor (TAGE/SC, indexed by PC and global history) and
   updated at commit. The FTB supplies presence and target; TAGE/SC
   supplies direction.

Summary: an FTB miss produces a fall-through prediction. For a
conditional branch, predecode provides branch presence and target;
direction is resolved at execute in the backend, which issues the
redirect on a mispredict. The FTB is updated with presence and target;
the directional predictor is updated at commit. See "Dataflow: the two
loops" in fe.md.
