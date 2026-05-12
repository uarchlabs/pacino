# bp_history Interface Specification
```
 FILE:    bp_history_interfaces.md
 SOURCE:  various
 STATUS:  DRAFT, reflects BP-002 PASS state
 UPDATED: 2026-03-28
 CONTACT: Jeff Nye
```

---

## Overview

bp_history owns all branch history state for the BP cluster:
the GHR (Global History Register), the PHR (Path History
Register), and all folded histories consumed by TAGE, ITTAGE,
and SC. It is owned by BPC (branch predictor cluster), not by
rename or dispatch. It contains no SRAM -- purely registered
state.

All types defined in bp_pkg.sv. This document describes port
semantics, timing contracts, and consumer/producer obligations.

---

## Module Parameters

None. All widths and depths are localparams from bp_pkg.sv.

  GHR_WIDTH      = 256   -- circular buffer depth in bits
  PHR_WIDTH      = 32    -- circular buffer depth in bits
  GHIST_PTR_BITS = 8     -- pointer into GHR buffer
  PHIST_PTR_BITS = 5     -- pointer into PHR buffer
  FTQ_DEPTH      = 64    -- number of checkpoint slots
  FTQ_IDX_BITS   = 6     -- index into checkpoint array

---

## Port List

  clk          : input  logic                       -- rising edge
  rstn         : input  logic                       -- active low

  -- Prediction update (speculative, one per active slot)
  pred_valid   : input  logic                       -- slot 0 active
  pred_taken   : input  logic                       -- slot 0 direction
  pred_pc      : input  logic [VA_WIDTH-1:0]        -- slot 0 fetch PC

  -- Checkpoint write
  ckpt_wr_en   : input  logic                       -- write enable
  ckpt_idx     : input  logic [FTQ_IDX_BITS-1:0]   -- FTQ slot index

  -- Rollback (redirect recovery)
  rollback_en  : input  logic                       -- restore enable
  rollback_ghist_ptr : input logic [GHIST_PTR_BITS-1:0]
  rollback_phist_ptr : input logic [PHIST_PTR_BITS-1:0]

  -- Current pointer outputs (for checkpoint write)
  ghist_ptr    : output logic [GHIST_PTR_BITS-1:0]
  phist_ptr    : output logic [PHIST_PTR_BITS-1:0]

  -- Folded history output (consumed by TAGE, ITTAGE, SC)
  folded       : output bp_folded_hist_t

Note: the port list above reflects the BP-002 implementation.
NUM_PRED_SLOTS extension (dual slot prediction update) is
deferred -- see Known Gaps.

---

## Prediction Update Interface

### Producer: BP cluster (one call per active prediction slot)
### Consumer: bp_history (GHR and PHR advance, folds update)

### Timing

  pred_valid, pred_taken, pred_pc are sampled on rising clk.
  GHR and PHR advance synchronously.
  Folded history outputs update on the same rising edge.
  Updated folds are available at the start of the next cycle.

### Semantics

  pred_valid = 0  -- no prediction this cycle. GHR, PHR, and
                     folds do not advance.
  pred_valid = 1  -- a prediction was made. Advance history.

  GHR update:
    ghr_mem[ghist_ptr] <= pred_taken
    ghist_ptr advances by 1 (modulo GHR_WIDTH).

  PHR update:
    phr_mem[phist_ptr] <= pred_pc[2] ^ pred_pc[3]
    phist_ptr advances by 1 (modulo PHR_WIDTH).

  Fold update (incremental, one fold per tagged table):
    bit_out  = ghr_mem[(ghist_ptr + H) % GHR_WIDTH]
    new_fold = (fold << 1) | pred_taken ^ fold[W-1] ^ bit_out
    where H is the history depth for that fold, W is fold width.

### Producer obligations

  - Must assert pred_valid exactly once per accepted prediction.
  - Must not assert pred_valid when no prediction is being made
    (e.g. on a stall or bubble cycle).
  - pred_pc must be the fetch block PC, not the branch PC.

---

## Checkpoint Interface

### Producer: BP cluster (writes on each accepted prediction)
### Consumer: bp_history (stores pointer snapshot per FTQ slot)

### Timing

  ckpt_wr_en and ckpt_idx are sampled on rising clk.
  The checkpoint captures the post-update pointer values
  (ghist_ptr and phist_ptr after the prediction advance).

### Semantics

  ckpt_wr_en = 0  -- no checkpoint write this cycle.
  ckpt_wr_en = 1  -- write current ghist_ptr and phist_ptr
                     into checkpoint slot ckpt_idx.

  Checkpoint stores: ghist_ptr (8b) + phist_ptr (5b) only.
  Folded histories are NOT stored per checkpoint slot.
  On rollback, folds are recomputed from buffer contents
  at the restored pointer (G15).

### Producer obligations

  - ckpt_idx must be a valid FTQ slot index (0 to FTQ_DEPTH-1).
  - ckpt_wr_en should be asserted in the same cycle as the
    prediction update (pred_valid=1) for the same slot.
  - Producer must not write the same ckpt_idx twice without
    an intervening rollback or FTQ slot reclaim.

---

## Rollback Interface

### Producer: BP cluster redirect/flush logic
### Consumer: bp_history (restores pointer, recomputes folds)

### Timing

  rollback_en, rollback_ghist_ptr, rollback_phist_ptr are
  sampled on rising clk.
  Pointer restore and fold recompute are synchronous.
  Restored folds are available at the start of the next cycle.

### Semantics

  rollback_en = 0  -- no rollback this cycle.
  rollback_en = 1  -- restore ghist_ptr and phist_ptr to the
                     provided values. Recompute all folds from
                     current ghr_mem and phr_mem contents at
                     the restored pointer positions.

  ghr_mem and phr_mem are NOT cleared on rollback.
  Entries written after the checkpoint remain in the buffer
  but are unreachable via the restored pointer. This is the
  accepted contamination model (see BP-002 TC8 confirmation).

### Producer obligations

  - rollback_ghist_ptr and rollback_phist_ptr must come from
    a previously written checkpoint slot (read from FTQ entry
    ghist_ptr and phist_ptr fields).
  - Producer must not assert rollback_en and pred_valid in
    the same cycle. Priority is undefined if both are asserted.

---

## Folded History Output Interface

### Producer: bp_history
### Consumer: TAGE (T1-T4 index and tag folds),
###           ITTAGE (IT1-IT4 index and tag folds),
###           SC (ST1-ST3 index folds)

### Timing

  folded is a registered output.
  Valid one cycle after the prediction update that caused the
  advance (same timing as ghist_ptr output).
  On rollback: folded reflects the recomputed state one cycle
  after rollback_en is asserted.

### Semantics

  folded is a bp_folded_hist_t packed struct. All fields are
  GHR-derived. PHR does not contribute to any fold in the
  current implementation (deferred -- see Known Gaps).

  TAGE folds (one set of three per tagged table T1-T4):
    tage_t<N>_idx_fh  -- index fold for T<N>
    tage_t<N>_tag_fh1 -- tag fold 1 for T<N>
    tage_t<N>_tag_fh2 -- tag fold 2 for T<N>

  ITTAGE folds (one set of three per table IT1-IT4):
    it_t<N>_idx_fh    -- index fold for IT<N>
    it_t<N>_tag_fh1   -- tag fold 1 for IT<N>
    it_t<N>_tag_fh2   -- tag fold 2 for IT<N>
    IT5 has no folds (BrIMLI table).

  SC folds (one index fold per table with history, ST1-ST3):
    sc_t1_idx_fh  -- width = SC_T1_HIST = 4b
    sc_t2_idx_fh  -- width = SC_T2_HIST = 10b
    sc_t3_idx_fh  -- width = SC_T3_HIST = 16b
    ST0 (hist=0) and ST4 (IMLI) have no folds.

### Consumer obligations

  - Consumers must not cache or register folded outputs
    independently. They must read folded directly each cycle.
  - Consumers must treat folded as invalid in the cycle
    immediately following rollback_en (recompute is in
    progress). This is a one-cycle window. Producer (cluster)
    must ensure no prediction fires in that cycle.
    (Timing impact TBD -- G15.)

---

## Pointer Output Interface

### Producer: bp_history
### Consumer: BP cluster (checkpoint write path)

  ghist_ptr : current GHR circular buffer pointer.
              Post-update value: reflects the advance from
              the most recent pred_valid=1.
  phist_ptr : current PHR circular buffer pointer.
              Same timing as ghist_ptr.

  These are the values the cluster writes into the FTQ entry
  (bp_ftq_entry_t.ghist_ptr and .phist_ptr) for checkpoint.

---

## Known Gaps and Deferred Items

| ID  | Item                                      | Status           |
|-----|-------------------------------------------|------------------|
| HI1 | NUM_PRED_SLOTS extension -- dual slot     | Deferred. Current|
|     | prediction update uses single pred_valid/ | impl is single   |
|     | pred_taken/pred_pc. Slot 1 update path    | slot only.       |
|     | not yet defined.                          | Resolve before   |
|     | See also G20 of PROJECT_STATUS            | bp_cluster impl. |
| HI2 | PHR contribution to fold index and tag    | Deferred to TAGE |
|     | hashing. Currently all folds are GHR-     | and ITTAGE impl  |
|     | derived only. PHR mixing TBD.             | sessions.        |
| HI3 | rollback_en + pred_valid same-cycle       | Priority undef.  |
|     | priority. Currently undefined behavior.   | Resolve before   |
|     |                                           | bp_cluster impl. |
| HI4 | One-cycle folded output invalid window    | G15 -- timing    |
|     | after rollback. Consumer must not fire    | impact TBD.      |
|     | prediction in that cycle. Enforcement     |                  |
|     | mechanism TBD.                            |                  |
| HI5 | Checkpoint slot reclaim protocol.         | TBD at FTQ impl. |
|     | When is a checkpoint slot safe to reuse?  |                  |

