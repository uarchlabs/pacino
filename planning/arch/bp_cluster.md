<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# BP Cluster Micro-Architectural Decisions

```
 FILE:    bp_cluster.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-09-17
 CONTACT: Jeff Nye
```
---

## Overview

8-issue OoO RISC-V RVA23 branch predictor cluster. Optionally dual
prediction (Xiangshan model): two predictions per 32-byte block, one
per prediction slot. THE SLOTS ARE THE BLOCK'S TWO BRANCH FIELDS, br0
and br1, NOT TWO NEXT-PC SLOTS: one lookup supplies both, and a taken
branch ends the block (fe_decisions.md 10, FE-10, FE-11). See Dual
Prediction Mode below. Dual mode is runtime-selectable via a static
configuration input. An earlier revision read "two independent
next-PC predictions per fetch bundle"; corrected session-070.

Predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS.

Override order (conditional branch direction and target):
  uBTB (p1) -> FTB, TAGE (p2) -> SC (p3)
  ON DIRECTION this IS a ranking: SC > TAGE > FTB, all three produce
  that one quantity, suspended per branch when the FTB fast path
  fires (ftb_confidence_override_rules.md 4.3, 4.2). ON EVERYTHING
  ELSE it is stage order, not a ranking: a later stage supersedes an
  earlier one (FE-3, fe_decisions.md 12, narrowed session-070), and
  targets are selected by branch type.
  Loop predictor overrides uBTB at p1 when trusted (override control
  decision). Loop predictor does not participate after p1.
  ITTAGE and RAS are outside this ordering (type-gated, see below).

---

## Block width

The successor on a uBTB miss is PC + FTB_BLOCK_BYTES, 32 bytes.

FTB_BLOCK_BYTES is 32, the PREDICTION block. FETCH_BLOCK_BYTES is
64, the FETCH block, a global parameter. `ftb_decisions.md` 2.3
rules that the two are independent and must not be collapsed:
treating the 64-byte fetch as a 64-byte prediction reintroduces a
two-block-per-cycle structure and would demand four
conditional-branch predictions per cycle against a two-prediction
budget.

AN EARLIER REVISION OF THIS DOCUMENT wrote the miss successor as
`PC + fetch_width` at both sites below. `fetch_width` here is
FETCH_BLOCK_BYTES, 64, so the successor skipped a whole prediction
block: the 32 bytes between PC+32 and PC+64 went unpredicted and a
branch in them was missed until the p2 redirect corrected it.
Bounded to one cycle, but a wrong successor is written into the FTQ
entry in the meantime. Corrected session-069.

The base is the lookup PC, not the aligned address containing it.
Prediction blocks are unaligned (`ftq_decisions.md` 4.7,
`ifu_decisions.md` IFU-6), and a miss does not resync the stream to
a 32-byte boundary.

---

## Predictor Hierarchy and Roles

### uBTB (micro Branch Target Buffer)
- Size:    256 entries, 4-way associative
- Stage:   p1 output
- Role:    First prediction. Provides next-PC to start speculative fetch.
           On miss: no prediction generated. Fetch proceeds
           sequentially (PC + FTB_BLOCK_BYTES, 32 bytes) until the
           p2 redirect fires. The base is the LOOKUP PC, not the
           32-byte-aligned address containing it, so a miss does
           not resync the stream to alignment.
           uBTB does not generate a redirect signal. It supplies or
           withholds an initial prediction only.

### Loop Predictor
- Size:    256 entries, 4-way associative
           LP_N_SETS = LP_TBL_ENTRIES / LP_TBL_WAYS = 64 sets
           LP_IDX_BITS = $clog2(64) = 6b
- Stage:   p1 output (same timing as uBTB)
- Role:    Detects loop branches and predicts exit. Overrides uBTB at
           p1 when loop predictor is trusted (high confidence).
           Trust decision made by override control, not internally.
- Parameters (all overridable at elaboration):
    LP_TBL_ENTRIES = 256
    LP_TBL_WAYS    = 4
    LP_TAG_BITS    = 14
    LP_ITR_BITS    = 14   -- iteration counter width
    LP_CNF_BITS    = 2    -- confidence counter width
    LP_AGE_BITS    = 8    -- age/replacement counter width
    LP_N_SETS      = LP_TBL_ENTRIES / LP_TBL_WAYS
    LP_IDX_BITS    = $clog2(LP_N_SETS), min 1
- Override: sits alongside uBTB in p1. Override control selects loop
           predictor output over uBTB when pred_is_loop and conf is
           sufficient. Does not participate in p2/p3 override chain.

### FTB (Fetch Target Buffer, aka BTB)
- Size:    2048 entries, 4-way associative, 512 sets
           FTB_WAYS = 4, FTB_ENTRIES = 2048, FTB_SETS = 512.
           `ftb_decisions.md` 2.2 and section 8 are the reference;
           do not restate the geometry here.
- Stage:   p2 output (p0 send, p1 registered, p2 valid)
- Role:    Authoritative branch target for direct conditional and
           unconditional branches. Identifies branch type per slot,
           gating which predictor provides the target at p2:
             return     -> RAS provides target
             indirect   -> ITTAGE provides target
             conditional -> TAGE provides direction, FTB provides target
             direct unc -> FTB provides target

### TAGE
- Stage:   p2 output (p0 index calc, p1 SRAM read + tag match, p2 final)
- Role:    Direction prediction for conditional branches. OVERRIDES
           THE FTB DIRECTION: the FTB submits its own direction for
           every valid conditional (conf MSB on ftb_brI_taken_p2)
           and TAGE supersedes it at p2. fe_decisions.md 3.3;
           ftb_confidence_override_rules.md 3.1, 4.3 and 8, where
           the direction priority is SC > TAGE > FTB.
           EXCEPT UNDER THE FAST PATH: when ftb_fastpath_p2[i]
           fires -- conf saturated and ftb_fastpath_en set -- the
           FTB direction stands for that branch and no TAGE or SC
           direction override is applied. TAGE and SC are still
           requested and still trained
           (ftb_confidence_override_rules.md 4.2, 6).
           THE REDIRECT IS A SEPARATE QUESTION. p2_redirect fires
           only when the successor the cluster would publish differs
           from the one its own p1 stage registers hold, not on the
           override itself: an override that does not change the
           successor fires nothing (fe_decisions.md FE-4, 2.5).
           An earlier revision read "p2_redirect fires on override";
           a session-070 revision then over-corrected and denied the
           direction override itself. Both corrected session-070.
- Tables:
    T0: 2 ways x 2048 entries, base table
        Entry layout: 2b CTR (no tag, no valid, no useful)
    T1: 2 banks x 2048, FH=8b,  FH1=8b,  FH2=7b,  hist=8b
    T2: 2 banks x 2048, FH=11b, FH1=8b,  FH2=7b,  hist=13b
    T3: 2 banks x 2048, FH=11b, FH1=8b,  FH2=7b,  hist=32b
    T4: 2 banks x 2048, FH=11b, FH1=8b,  FH2=7b,  hist=119b
    T1-T4 tagged entry layout:
        valid  : 1b
        tag    : 8b
        ctr    : 3b
        useful : 2b

### SC (Statistical Corrector)
- Stage:   p3 output. The SC path STARTS AT p2, not p0: the TAGE p2
           result and the p0 inputs staged forward are presented at
           p2, the table index hashes are computed at p2, the table
           RAM reads issue at p2, and the result is valid at p3. The
           update path is u0/u1. sc_decisions.md 2 and 9,
           sc_interfaces.md Timing, sc_table_interfaces.md Table
           Pipeline, bp_arb_spec.md 6.1. An earlier revision read
           "p0 index, p1 counter read, p2 accumulate, p3 final",
           which is a four-stage path this design does not have.
           Corrected session-070.
- Role:    Corrects TAGE when TAGE is systematically biased. Requires
           TAGE output to proceed (TAGE must be valid before SC can
           finalize). Overrides TAGE direction when combined counter
           magnitude exceeds threshold, subject to the FTB fast
           path (ftb_confidence_override_rules.md 4.2). The p3
           redirect fires only when SC CHANGES WHAT THE CLUSTER
           PUBLISHED AT p2, not on the override itself
           (fe_decisions.md 3.1, FE-4). An earlier revision read
           "p3_redirect fires on override"; corrected session-070.
           Threshold: dynamically adapted at runtime (O-GEHL scheme,
           TC counter), not a fixed design-time value and not CSR-
           configurable. See sc_decisions.md sections 9-10, G7.

- Tables:
    ST0: 512 entries, direct mapped, 6b wide, hist=0b
         No folded history (hist=0).
    ST1: 512 entries, direct mapped, 6b wide, hist=4b
    ST2: 512 entries, direct mapped, 6b wide, hist=16b
    ST3: 512 entries, direct mapped, 6b wide, hist=64b
    ST4: 1024 entries, direct mapped, 6b wide, hist=none
         No folded history (BrIMLI index, not a hashed fold).

### ITTAGE (Indirect Target TAGE)
- Stage:   p2 output (p0 index and tag hash, p1 SRAM read + tag
           match, p2 final target)
- Role:    Target prediction for indirect non-return branches (JALR
           non-return). Target stored directly in the ITTAGE tables --
           no base+offset secondary LUT. Active only when FTB
           identifies branch type as indirect.
- Target:  38b, the upper 38 bits of a Sv39 VA. Bit 0 is always zero
           for instruction alignment and is not stored.
           IT_MAX_TGT_WIDTH = 38, NOT widened for VA_WIDTH 41:
           predictor storage may mispredict where an architectural
           address may not (fe_decisions.md FE-19). The
           reconstruction must zero-extend rather than sign-extend;
           TD#122. See ittage_interfaces.md.
- Tables:
    IT1: 2 banks x 256 entries, FH=4b,  FH1=4b,  FH2=4b,  hist=4b
    IT2: 2 banks x 256 entries, FH=8b,  FH1=8b,  FH2=8b,  hist=8b
    IT3: 2 banks x 512 entries, FH=9b,  FH1=9b,  FH2=8b,  hist=13b
    IT4: 2 banks x 512 entries, FH=9b,  FH1=9b,  FH2=8b,  hist=16b
    IT5: 2 banks x 512 entries, FH=9b, FH1=9b, FH2=8b, hist=32b

### RAS (Return Address Stack)
Dual-stack, static partition. 16 speculative + 32 commit entries.
See planning/arch/ras_decisions.md for full decision rationale.

#### Speculative stack
- Structure: simple circular buffer, pointer-only snapshot recovery.
             Linked circular array considered and rejected session-050.
             See planning/arch/ras_decisions.md section 3.2.
- Entries:   16
- Entry fields:
    ret_addr  : VA_WIDTH bits -- PC+2 or PC+4 of instruction after call
    rctr      : 4b            -- recursion counter, see ras_decisions.md
                                 section 5
- Pointers:
    TOSR  -- Top Of Stack Read: current top for predictions
    TOSW  -- Top Of Stack Write: next free allocation slot
    BOS   -- Bottom Of Stack: boundary of committed state
- Push:  write to TOSW slot, TOSR = TOSW, TOSW advances
- Pop:   present TOSR entry as prediction, TOSR decrements.
         No data overwritten.
- Redirect recovery: restore (TOSR, TOSW, BOS) from FTQ snapshot.
  Pointer-only restore; no push/pop replay needed.
- Empty fallback: when speculative stack empty during pop, commit
  stack top used as prediction result without consuming the entry.

#### Commit stack
- Structure: conventional circular stack
- Entries:   32
- Entry fields: ret_addr (VA_WIDTH bits), rctr (4b)
- Pointer: CSP -- Commit Stack Pointer, points to current top
- Update:  on call commit from FTQ, push return address, CSP
           advances, BOS in speculative stack updated.
           On return commit, CSP decrements.

#### Pipeline stages
- p2: reads FTB structural prediction; executes push (call) or pop
      (return); produces spec_pop_addr.
- p3: checks if p3 structural prediction disagrees with p2; applies
      inverse repair operation if needed.

  p2/p3 repair table:
    p2=push, p3=no-op  -> repair: pop
    p2=no-op, p3=pop   -> repair: pop
    p2=pop,  p3=no-op  -> repair: push
    p2=no-op, p3=push  -> repair: push
  Note: push->pop and pop->push within one p2/p3 pair cannot occur.

#### Call and return detection (RISC-V register conventions)
JAL pushes when rd = x1 or x5, and does nothing otherwise.

JALR follows the RISC-V hint table exactly. Link means x1 or x5:

```
  rd      rs1     rs1 == rd    RAS action
  !link   !link   --           none
  !link   link    --           pop          RETURN
  link    !link   --           push         call
  link    link    no           pop, push    RETURN_CALL
  link    link    yes          push         call
```

The compressed forms map onto that table, they are not extra cases:

```
  C.JR   rs1        = JALR x0, rs1, 0.  rd = x0, never link.
                      rs1 link  -> pop.  rs1 !link -> none.
  C.JALR rs1        = JALR x1, rs1, 0.  rd = x1, ALWAYS link.
                      rs1 = x1  -> rs1 == rd   -> push.
                      rs1 = x5  -> both, unequal -> pop, push.
                      rs1 !link -> push.
```

SO C.JALR IS NEVER A POP-ONLY RETURN, and a JALR is a return only
when rd is not a link register.

  Two earlier revisions were wrong here. The first read "Return:
  JALR, C.JR, C.JALR where rs1 = x1 or x5 (C.JALR with rs1=x5
  excluded from return classification)", which made C.JALR with
  rs1=x1 a return and omitted the rd constraint, so a JALR with a
  link rd read as a return. A session-070 rewrite then gave the push
  case as "rd = x1 or x5 and rs1 not a link register", which drops
  the rs1 == rd row, leaving JALR x1, x1 in no class at all. The
  table above is the fix for both. ras_decisions.md 2 is canonical
  and agrees. Corrected session-070.

#### Role in JALR prediction
- RAS:    JALR/C.JR/C.JALR matching return register convention.
          Type-gated at p2.
- ITTAGE: every other indirect JALR. Not "remaining" by target
          stability -- ITTAGE is consulted for all of them.
- FTB:    the FALLBACK, not a third arm. The FTB target stands when
          ITTAGE misses (ftb_decisions.md 4.2), whatever the target's
          stability. An earlier revision read "three-way split" with
          "FTB: JALR with fixed stable target (most direct calls)",
          which makes the FTB a type-based arm. Selection is by
          ITTAGE hit, not by branch flavour. fe_decisions.md 3.3.
          Corrected session-070.

#### Stage and update notes
- Stage:  p2 push/pop + spec_pop_addr; p3 = p2 registered
- Update: speculative at p2 (separate from main update channels)
          commit stack updated at retire/commit, not post-execute
- Outside the conditional branch override chain.

---

## Pipeline Staging

  Cycle N   (p0): PC input. Index calculations begin in the
                  predictors that index at p0.
                  FTB, TAGE, ITTAGE send address to SRAM.
                  SC DOES NOT. Its path starts at p2; see the SC
                  Stage bullet. An earlier revision listed SC here
                  and at p1; corrected session-070.

  Cycle N+1 (p1): uBTB output valid -> first prediction available.
                  Loop predictor output valid -> overrides uBTB if
                  trusted (override control gates selection).
                  Fetch begins speculatively on p1 result.
                  On uBTB miss and loop predictor not trusted: fetch
                  proceeds PC + FTB_BLOCK_BYTES.
                  TAGE: SRAM read completes, tag match, slot reorder.
                  FTB: result registered (arrives too late for p1).
                  SC: nothing. It has not started.

  Cycle N+2 (p2): FTB output valid (registered from p1).
                  TAGE final result valid.
                  RAS: push/pop executes, spec_pop_addr valid.
                  ITTAGE: final target valid.
                  SC STARTS HERE: the TAGE p2 result and the staged
                      p0 inputs are presented, index hashes are
                      computed, and the table RAM reads issue. Result
                      at p3. sc_decisions.md 2 and 9,
                      sc_table_interfaces.md Table Pipeline.
                  p2_redirect fires if FTB/TAGE/RAS/ITTAGE disagrees
                  with p1.
                  FTB entry saved for one additional cycle (-> p3).

  Cycle N+3 (p3): SC final result valid -> p3_redirect if SC != p2.
                  RAS p3 = p2 registered. Stack repair if p3 != p2.
                  FTB entry from p2 held and available.

---

## Redirect Architecture

Two redirect points downstream of p1:

  p2_redirect: fires when the successor the cluster would publish at
               p2 differs from the one ITS OWN p1 STAGE REGISTERS
               HOLD. NOT "disagrees with uBTB p1": the p1 successor
               is the uBTB's OR the loop predictor's, whichever the
               p1 mux selected (fe_decisions.md 2.5, and the Loop
               predictor line in the Overview above). Naming the uBTB
               is wrong whenever the LP won the mux. The comparison
               is one quantity against the cluster's own staged view,
               never predictor against predictor (FE-4). Corrected
               session-070.
               Target selection at p2 by branch type:
                 return     -> RAS spec_pop_addr
                 indirect   -> ITTAGE (final; FTB target on miss)
                 conditional -> TAGE direction + FTB target
                 direct     -> FTB target
               TAGE overrides FTB direction (conditional only).
               RAS and ITTAGE are type-gated, not in the
               TAGE/FTB override chain.

  p3_redirect: fires when SC CHANGES THE SUCCESSOR the cluster
               published at p2 -- not whenever SC overrides the
               TAGE direction. An override that leaves the next
               fetch address unchanged fires nothing
               (fe_decisions.md 3.1, FE-4; SC Role above;
               sc_interfaces.md Consumer obligations). This read
               "fires when SC overrides TAGE direction from p2".
               Session-070.
               SC requires TAGE output as input; SC cannot finalize
               before TAGE. Target for p3_redirect comes from FTB
               (held from p2). Direction comes from SC.
               No predictor produces a new target at p3.

Note: uBTB does not generate a redirect. It provides or withholds an
initial prediction only. The override chain starts at p2.

---

## Dual Prediction Mode

Configuration: static input dual_pred_en (1 = dual, 0 = single).

Mechanism: the two slots are the two BRANCH FIELDS of ONE 32-byte
prediction block, br0 and br1, each located by its own pos within
the block's 16 two-byte positions. One lookup supplies both
(fe_decisions.md 10, FE-10). They are not two next-PC slots and not
two PC ranges.

A TAKEN BRANCH ENDS THE BLOCK. FE-11: a RAS-operating instruction,
and any taken branch, terminates the block, so slot 1 is not
reached when slot 0 is taken. An earlier revision said the slots
allow "a taken branch in the middle of a bundle to also predict the
branch at the predicted target", which describes a second
prediction past a taken branch. That cannot happen.

dual_pred_en DOES NOT CHANGE THE STRUCTURE. The slots and the
channels exist either way (fe_decisions.md 10). At dual_pred_en=0
only br0 is reported and only upd_ch[0] carries traffic; nothing is
removed. An earlier revision read "One update channel: upd_ch[0]
only", which reads as a structural difference. Corrected
session-070.

When dual_pred_en=1:
  - Both br0 and br1 reported per block.
  - Both update channels carry traffic: upd_ch[0] and upd_ch[1].
  - Each channel handles both conditional and indirect resolution.

When dual_pred_en=0:
  - Only br0 reported.
  - Only upd_ch[0] carries traffic. upd_ch[1] still exists.

---

## History Module

Centralized ownership of all branch history state. Owned by BPC,
not rename/dispatch. No SRAM -- purely registered state.

### Registers

GHR (Global History Register):
  Width:  GHR_WIDTH = 256b circular buffer
  Pointer: ghist_ptr (GHIST_PTR_BITS = 8b), OWNED BY bp_history
  Update: speculative on each prediction. Write pred_taken into
          buffer at ghist_ptr position, one write per active
          prediction slot in priority order.
  Restore: on redirect, bp_history restores its own pointer from
           the checkpoint the rollback INDEX names. No pointer
           value is supplied from outside. bp_history_decisions.md
           2 and 10, bp_history_interfaces.md Pointer Ownership.
           This read "driven externally" and "accept new ghist_ptr
           from external logic". Session-070.
           Recompute all folded histories from buffer contents.

PHR (Path History Register):
  Width:  PHR_WIDTH = 32b circular buffer
  Pointer: phist_ptr (PHIST_PTR_BITS = 5b), OWNED BY bp_history
  Update: speculative on each prediction:
            PHR[phist_ptr] = pred_pc[2] ^ pred_pc[3]
          One write per active prediction slot in priority order.
          Bit selection (pc[2] ^ pc[3]) is subject to tuning.
  Restore: as ghist_ptr above -- bp_history restores from the
           checkpoint index, not from a supplied pointer value.
           Same policy as GHR.

PHR folding is deferred. bp_history.sv maintains phr_mem and
exposes phr_buf, but PHR does not contribute to any fold in
bp_folded_hist_t. All current folds are GHR-derived only.
PHR contribution to index and tag hashing is TBD, tracked by
bp_history_decisions.md HI2 and tage_interfaces.md TI1. It is NOT
resolved: an earlier revision said "resolved at TAGE and ITTAGE
implementation sessions", and both units are now Complete and green
with the question still open under HI2. Corrected session-070. The
same statement appears under Folded Histories below; this is the
one question, not two.

### Folded Histories

All folded histories maintained incrementally inside this module.
Consumers (TAGE, ITTAGE, SC) read folded outputs directly.
Exposed via bp_folded_hist_t packed struct output port.

One set of three folds per tagged TAGE table (T1-T4):
  tage_t<N>_idx_fh  -- index fold, width = FH for T<N>
  tage_t<N>_tag_fh1 -- tag fold 1, width = FH1 for T<N>
  tage_t<N>_tag_fh2 -- tag fold 2, width = FH2 for T<N>

One set of three folds per ITTAGE table (IT1-IT5):
  it_t<N>_idx_fh    -- index fold, width = FH for IT<N>
  it_t<N>_tag_fh1   -- tag fold 1, width = FH1 for IT<N>
  it_t<N>_tag_fh2   -- tag fold 2, width = FH2 for IT<N>

One index fold per SC table with history (ST1-ST3):
  sc_t1_idx_fh  -- width = SC_TBL_HIST[1] = 4b
  sc_t2_idx_fh  -- width = SC_TBL_HIST[2] = 16b
  sc_t3_idx_fh  -- width = SC_TBL_HIST[3] = 64b

Incremental fold update rule for fold of width W, history H:
  bit_out  = ghr_mem[(ghist_ptr + H) % GHR_WIDTH]
  new_fold = (fold << 1) | new_bit ^ fold[W-1] ^ bit_out
  where new_bit is the incoming pred_taken.

On redirect: recompute all folds from circular buffer contents
at the restored pointer position (combinational, G15).

PHR/GHR mixing for index and tag hashing is the same open question
as the one under History Module above: HI2 and TI1. Not resolved at
the TAGE and ITTAGE sessions, which have happened. Corrected
session-070.

### Checkpoints

One checkpoint slot per FTQ entry (FTQ_DEPTH = 64 slots).
Each slot stores: ghist_ptr (8b) and phist_ptr (5b) only.
Folded histories are NOT checkpointed -- recomputed on rollback.
Implemented as register arrays indexed by FTQ_IDX_BITS.
Checkpoint written with post-update pointer values.

---

## Update Policy

Update trigger: post-execute resolution. No wait for retire.
Both update channels exist in either mode. At dual_pred_en=0 only
upd_ch[0] carries traffic; upd_ch[1] is still there (Dual Prediction
Mode above, fe_decisions.md 10). This read "Two update channels when
dual_pred_en=1, one when dual_pred_en=0", a structural difference
there is not. Session-070.
Each channel carries both conditional and indirect branch resolution
(they are one combined channel, not split by type).

RAS update: speculative at p2 (separate from main update channels).
Checkpoint/restore: the RAS snapshot (tosr, tosw, bos) is written
into the FTQ entry at prediction and restored from it on redirect.
Pointer-only; the circular data is not cleared. A flush is a
redirect (FE-14), so there is no separate flush protocol. The
mechanism is ras_restore_val / ras_restore_snapshot, built in
ras.sv and driven by tb_ras. Nothing here is deferred to
rename/dispatch. ras_decisions.md 4.3 and 4.4 are the single
source; do not restate or re-derive the protocol here.

Prediction phase pre-computes meta-data needed for updates and
stores it alongside the prediction result. Update path reads this
stored meta-data rather than recomputing on resolution.

---

## FTQ Entry Split

MOVED 2026-08-19. This section carried a copy of the FTQ entry
layout. The sole prose home is now planning/arch/ftq_entry_formats.md;
bp_structs_pkg.sv remains the reference declaration.

The FTQ entry is two structures in two SRAMs, both indexed by the FTQ
entry index: bp_ftq_entry_t on the fast path, read every cycle, and
bp_ftq_meta_t on the slow path, carried per prediction slot and read
only at post-execute update. What the cluster contributes to each is
ftq_bpu_interfaces.md sections 4, 4a, 7.1 and 7.2.

---

## Known Gaps and TBDs

Open items and TBDs for this document are tracked in
PROJECT_STATUS.md -- BP Cluster Open TBDs section.

## Settled Implementation Details

Parameter values derived in bp_defines_pkg.sv:
  TAGE_MAX_AWIDTH    = $clog2(2048) = 11  (max table depth)
  TAGE_TBL_SEL_WIDTH = $clog2(5)   = 3   (5 tables T0-T4)
  TAGE_MAX_DWIDTH    = TAGE_TAG_BITS = 8  (tag is widest alloc field)
  TAGE_CTR_BITS      = 3                  (max: T0=2b, T1-T4=3b)
  SC_NUM_TABLES      = 5                  (ST0-ST4)
  FTQ_CONF_BITS      = 4                  (confidence placeholder)

SC table roles are prose, not parameters: ST0-ST3 hold the
confidence counters and ST4 is the BrIMLI table. See
sc_decisions.md 6.

SC index array (superseded session-056; sc_imli_idx split retired):
  sc_upd_idx [0:SC_NUM_TABLES-1][SC_MAX_IDX_WIDTH-1:0]
  sc_upd_ctr [0:SC_NUM_TABLES-1][SC_MAX_CTR_WIDTH-1:0]
  Uniform 5-entry arrays (ST0-ST4). The original BP-001 rationale
  (ST4 index width differs, cannot form a uniform array) no longer
  applies -- indices/counters are packed 2D arrays sized to the max
  width across tables (session-058), zero-extended per table as
  needed. See sc_decisions.md section 9, bp_structs_pkg.sv.

RAS snapshot bundled as bp_ras_snapshot_t sub-struct within
bp_ftq_entry_t. Access pattern: entry.ras.tosr, .tosw, .bos.
Pointer width: RAS_PTR_BITS = $clog2(16) = 4b each field.
See planning/arch/ras_decisions.md section 4.

FTQ entry history checkpoint (BP-002):
  ghr_snapshot (256b) removed from bp_ftq_entry_t.
  Replaced with ghist_ptr (8b) and phist_ptr (5b).
  Folded histories recomputed on rollback, not stored per slot.
  Implemented in bp_structs_pkg.sv.

---

## Timing Methodology Gap

Verilator does not provide timing data. Stage notation in struct
comments expresses intent to Claude Code but is not verified by any
automated tool. Jeff reviews RTL directly for timing correctness.
This is documented as a known methodology gap.

Timing intent for BP cluster structs uses the prediction pipeline
stages, not the decoder's P-stages:
  p0.comb = combinational in p0
  p1.clk  = registered at end of p1 (available start of p2)
  etc.

The decoder's P0/P1 and the prediction pipeline's p0/p1 are now
distinguished by case alone. Struct comments in bp_structs_pkg.sv
were not inspected in this pass and may still carry s-stage labels.

---

## Methodology Notes

This is the second case study for the AI-assisted co-design methodology
writeup. Complexity drivers vs. the decoder track:
  - Micro-architectural decisions were open (not spec-driven)
  - Interfaces not predetermined by any external spec
  - Multi-module consistency is a real challenge (7 predictor
    modules plus bp_history and the cluster top, all sharing
    bp_defines_pkg.sv and bp_structs_pkg.sv)
  - Timing budget spans 3 cycles with conditional redirect paths
Raw observations to be captured in docs/observations/ during BP work.

---

## Document History

  2026-05-18  Session-025 baseline.
  2026-06-23  Session-050. RAS section updated: static partition
              decision recorded (16 spec + 32 commit). Linked-list
              structure retained in section for reference alongside
              new decisions; full rationale in ras_decisions.md.
              ftq_entry_t ras field comment corrected: 6b -> 4b
              (RAS_PTR_BITS = $clog2(16) = 4b). Settled
              implementation details: RAS snapshot pointer width
              noted.
  2026-08-19  FTQ Entry Split rewritten to match bp_structs_pkg.sv.
              The rev 1.0 entry was pre-dual-slot: target, br_type,
              taken, pred_src and confidence were block-scalar and
              there was no pos field. They are now per slot in
              bp_ftq_slot_t [NUM_PRED_SLOTS-1:0], declared inside
              bp_ftq_entry_t, and pos is added. Type names corrected
              to bp_ftq_entry_t / bp_ftq_meta_t. branch_id restated
              as the FTQ ENTRY index (TD-FE-5). Slow path restated
              as five nested predictor metadata types rather than a
              flattened field list; the lp member is lp_pred_t and
              the retired bp_loop_meta_t spellings lp_pst_itr and
              lp_cur_itr are gone (TD#106, BP-092); ftb_pred_meta_t
              added (IC-FTB-10). Per-slot carry of bp_ftq_meta_t and
              the disjoint p2/p3 write groups recorded. Widths
              stated: slot 55b, entry 182b at NUM_PRED_SLOTS = 2.

  2026-08-19  bp_ftq_entry_t gains pft_addr, the block fall-through,
              VA_WIDTH wide and block scalar. Successor selection is
              re-evaluated on every redirect (fe_decisions.md 2.4)
              and the not-taken arm is bpu_pred_pft_p1, which arrives
              only at p1, so the value must be stored. Entry width
              182b -> 222b, block-scalar subtotal 72b -> 112b.
              Applied to bp_structs_pkg.sv and checked in
              tb_bp_pkg.sv (ENTRY_BITS, a field width check and the
              block-scalar preservation check). All 47 bpu targets
              green.

  2026-08-19  Slow path restated as the TD-FE-2 overload scheme: a
              two-arm packed union, u.cond {tage, sc, lp} against
              u.ind {ittage}, with ftb outside it. 420b -> 277b per
              slot. Defined and deferred: a storage optimization
              only. The arm is decoded from the fast-path
              bp_ftq_slot_t.br_type, which carries the FTB
              classification once the slot correction group of
              fe_decisions.md 2.5 writes it (TD-FE-6). Definition
              and the write/read rules are ftq_entry_formats.md 3.1;
              this section carries the layout and the widths only.

  2026-08-19  FTQ Entry Split reduced to a pointer. The layout it
              carried moved to planning/arch/ftq_entry_formats.md,
              which is now the only prose copy. This document had
              held a third copy alongside fe_decisions.md and the
              package, and all three were being edited in lockstep.

  2026-09-15  session-069. The uBTB-miss successor is PC +
              FTB_BLOCK_BYTES (32), not PC + fetch_width (64).
              fetch_width is FETCH_BLOCK_BYTES and collapsing the
              two is banned by ftb_decisions.md 2.3. Corrected at
              both sites; new Block width section states the base
              is the lookup PC, not the aligned address.

  2026-09-17  FTB associativity corrected from 8-way to 4-way,
              512 sets. This was the last surviving copy of the
              "FTB_WAYS currently 8" draft annotation that
              ftb_decisions.md struck in session-053 when BP-065
              confirmed the package at 4; this document was not
              swept at the time. 4-way is what is built:
              bp_defines_pkg.sv FTB_WAYS = 4, and ftb_cntrl.sv
              plru_victim / plru_touch implement a 3-bit four-way
              tree-PLRU. The geometry now cites ftb_decisions.md
              rather than restating it, since restating it is how
              the stale copy survived.

              Three unrelated repairs in the same pass. The SC
              heading read "#design## SC" and rendered as body
              text, not a heading. Methodology Notes cited
              bp_pkg.sv, deleted at the session-008 package split;
              it is bp_defines_pkg.sv and bp_structs_pkg.sv. The
              same line said 6 predictor modules; there are seven,
              plus bp_history and the cluster top, which is what
              bp_cluster.sv instantiates. Document History was not
              in date order -- the session-069 entry sat above four
              older ones -- and is now sorted.

  2026-09-17  ITTAGE corrected to p2. The Stage bullet, the Pipeline
              Staging block and Redirect Architecture all carried a
              raw-at-p2 / final-at-p3 split with a p3 refinement of
              the indirect target. That split was removed from
              fe_decisions.md on 2026-07-23 as an artifact of the
              base+offset LUT scheme, which Pacino does not use; this
              document was not swept. p2 is confirmed by
              fe_decisions.md 1, ittage_interfaces.md (p0 hash, p1
              SRAM read and tag match, p2 final target) and the RTL:
              ittage.sv and ittage_cntrl.sv declare only
              ittage_pred_rdy_p2 and ittage_pred_meta_p2, and contain
              no p3 signal. Closes TD#42.

              ITTAGE target width corrected. It read "stored directly
              as VA_WIDTH bits" with VA_WIDTH 40b. It is 38b, the
              upper 38 bits of a Sv39 VA with bit 0 not stored
              (ittage_interfaces.md; IT_MAX_TGT_WIDTH = 38). The
              scheme -- target held in the ITTAGE tables, no
              base+offset LUT -- was already correct here.

              Stage labels converted from s0-s3 to p0-p3 throughout,
              50 sites including p2_redirect and p3_redirect and the
              RAS repair table. The stages are identical; only the
              label changes (sc_decisions.md 3). Timing Methodology
              Gap reworded to match.

              Overview override chain annotated with stages:
              uBTB (p1) -> FTB, TAGE (p2) -> SC (p3). The bare
              "SC > TAGE > FTB > uBTB" was stage order written
              without the labels, which fe_decisions.md 12 reads as a
              contention ranking and rejects. With the labels it is
              FE-3 supersession. The one real intra-stage rule, TAGE
              over FTB direction within p2, is stated.

              SC_NUM_MAIN_TBLS and SC_NUM_ALL_TBLS replaced by
              SC_NUM_TABLES = 5. Neither name appears in
              sc_decisions.md or sc_table_interfaces.md, and this
              section already used SC_NUM_TABLES four lines below in
              the sc_upd_idx / sc_upd_ctr declarations. The ST0-ST3
              versus ST4 split that SC_NUM_MAIN_TBLS encoded is real
              but is prose in sc_decisions.md 6, not a parameter, and
              is restated as such here.

              RAS checkpoint/restore "Policy TBD at rename/dispatch"
              replaced by a pointer to ras_decisions.md 4.3 and 4.4.
              The protocol is decided and built: pointer-only restore
              of tosr/tosw/bos from the FTQ snapshot, no separate
              flush path because a flush is a redirect (FE-14),
              implemented as ras_restore_val /
              ras_restore_snapshot in ras.sv with tb_ras coverage.
              RAS-3 closed 2026-08-20. ras_decisions.md 4.4.2 lists
              the stale OPEN markers that caused that item to be
              re-raised repeatedly; this line was one more, and it
              also named the wrong owner -- the History Module
              section of this document already states that
              speculative predictor state is owned by the BPC, not
              rename/dispatch.

