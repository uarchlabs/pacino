<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# BP Cluster Micro-Architectural Decisions

```
 FILE:    bp_cluster.md
 SOURCE:  various
 STATUS:  STABLE (rev 1.0)
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```
---

## Overview

8-issue OoO RISC-V RVA23 branch predictor cluster. Optionally dual
prediction (Xiangshan model): two independent next-PC predictions per
fetch bundle, one per prediction slot. Dual mode is runtime-selectable
via a static configuration input.

Predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS.

Override chain (conditional branch direction and target):
  SC > TAGE > FTB > uBTB
  Loop predictor overrides uBTB at s1 when trusted (override control
  decision). Loop predictor does not participate in s2/s3 chain.
  ITTAGE and RAS are outside this chain (type-gated, see below).

---

## Predictor Hierarchy and Roles

### uBTB (micro Branch Target Buffer)
- Size:    256 entries, 4-way associative
- Stage:   s1 output
- Role:    First prediction. Provides next-PC to start speculative fetch.
           On miss: no prediction generated. Fetch proceeds sequentially
           (PC + fetch_width) until s2 redirect fires.
           uBTB does not generate a redirect signal. It supplies or
           withholds an initial prediction only.

### Loop Predictor
- Size:    256 entries, 4-way associative
           LP_N_SETS = LP_TBL_ENTRIES / LP_TBL_WAYS = 64 sets
           LP_IDX_BITS = $clog2(64) = 6b
- Stage:   s1 output (same timing as uBTB)
- Role:    Detects loop branches and predicts exit. Overrides uBTB at
           s1 when loop predictor is trusted (high confidence).
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
- Override: sits alongside uBTB in s1. Override control selects loop
           predictor output over uBTB when pred_is_loop and conf is
           sufficient. Does not participate in s2/s3 override chain.

### FTB (Fetch Target Buffer, aka BTB)
- Size:    2048 entries, 8-way associative
- Stage:   s2 output (s0 send, s1 registered, s2 valid)
- Role:    Authoritative branch target for direct conditional and
           unconditional branches. Identifies branch type per slot,
           gating which predictor provides the target at s2:
             return     -> RAS provides target
             indirect   -> ITTAGE provides target
             conditional -> TAGE provides direction, FTB provides target
             direct unc -> FTB provides target

### TAGE
- Stage:   s2 output (s0 index calc, s1 SRAM read + tag match, s2 final)
- Role:    Direction prediction for conditional branches. Overrides FTB
           direction when TAGE disagrees. s2_redirect fires on override.
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

#design## SC (Statistical Corrector)
- Stage:   s3 output (s0 index, s1 counter read, s2 accumulate, s3 final)
- Role:    Corrects TAGE when TAGE is systematically biased. Requires
           TAGE output to proceed (TAGE must be valid before SC can
           finalize). Overrides TAGE direction when combined counter
           magnitude exceeds threshold. s3_redirect fires on override.
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
- Stage:   s3 output (s0 index, s1 SRAM read, s2 raw prediction, s3 final)
- Role:    Target prediction for indirect non-return branches (JALR
           non-return). Target stored directly as VA_WIDTH bits -- no
           base+offset secondary LUT. Active only when FTB identifies
           branch type as indirect.
- VA_WIDTH: 40b (parameter, covers RVA23 implementation VA space)
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
- s2: reads FTB structural prediction; executes push (call) or pop
      (return); produces spec_pop_addr.
- s3: checks if s3 structural prediction disagrees with s2; applies
      inverse repair operation if needed.

  s2/s3 repair table:
    s2=push, s3=no-op  -> repair: pop
    s2=no-op, s3=pop   -> repair: pop
    s2=pop,  s3=no-op  -> repair: push
    s2=no-op, s3=push  -> repair: push
  Note: push->pop and pop->push within one s2/s3 pair cannot occur.

#### Call and return detection (RISC-V register conventions)
- Call:   JAL, JALR, C.JALR  where rd = x1 or x5
- Return: JALR, C.JR, C.JALR where rs1 = x1 or x5
          (C.JALR with rs1=x5 excluded from return classification)

#### Role in JALR prediction (three-way split with FTB and ITTAGE)
- FTB:    JALR with fixed stable target (most direct calls)
- RAS:    JALR/C.JR/C.JALR matching return register convention
- ITTAGE: remaining indirect JALR with history-dependent targets

#### Stage and update notes
- Stage:  s2 push/pop + spec_pop_addr; s3 = s2 registered
- Update: speculative at s2 (separate from main update channels)
          commit stack updated at retire/commit, not post-execute
- Outside the conditional branch override chain.

---

## Pipeline Staging

  Cycle N   (s0): PC input. Index calculations begin in all predictors.
                  FTB, TAGE, SC, ITTAGE send address to SRAM.

  Cycle N+1 (s1): uBTB output valid -> first prediction available.
                  Loop predictor output valid -> overrides uBTB if
                  trusted (override control gates selection).
                  Fetch begins speculatively on s1 result.
                  On uBTB miss and loop predictor not trusted: fetch
                  proceeds PC+fetch_width.
                  TAGE: SRAM read completes, tag match, slot reorder.
                  SC: saturating counter read.
                  FTB: result registered (arrives too late for s1).

  Cycle N+2 (s2): FTB output valid (registered from s1).
                  TAGE final result valid.
                  RAS: push/pop executes, spec_pop_addr valid.
                  ITTAGE: raw prediction available.
                  SC: accumulates TAGE provider counter + SC counter,
                      computes abs value vs threshold (result pending s3).
                  s2_redirect fires if FTB/TAGE/RAS disagrees with s1.
                  FTB entry saved for one additional cycle (-> s3).

  Cycle N+3 (s3): SC final result valid -> s3_redirect if SC != s2.
                  ITTAGE final result valid.
                  RAS s3 = s2 registered. Stack repair if s3 != s2.
                  FTB entry from s2 held and available.

---

## Redirect Architecture

Two redirect points downstream of s1:

  s2_redirect: fires when FTB/TAGE/RAS result disagrees with uBTB s1.
               Priority for target selection at s2:
                 return     -> RAS spec_pop_addr
                 indirect   -> ITTAGE (raw, pre-s3 final)
                 conditional -> TAGE direction + FTB target
                 direct     -> FTB target
               TAGE overrides FTB direction (conditional only).
               RAS and ITTAGE are type-gated, not in the
               TAGE/FTB override chain.

  s3_redirect: fires when SC overrides TAGE direction from s2.
               SC requires TAGE output as input; SC cannot finalize
               before TAGE. Target for s3_redirect comes from FTB
               (held from s2). Direction comes from SC.
               ITTAGE final result also available at s3 -- may refine
               indirect target if s2 used raw ITTAGE result.

Note: uBTB does not generate a redirect. It provides or withholds an
initial prediction only. The override chain starts at s2.

---

## Dual Prediction Mode

Configuration: static input dual_pred_en (1 = dual, 0 = single).
Mechanism: same as Xiangshan -- two independent next-PC slots per
fetch bundle, allowing a taken branch in the middle of a bundle to
also predict the branch at the predicted target.

When dual_pred_en=1:
  - Two prediction slots active per fetch bundle.
  - Two independent update channels: upd_ch[0] and upd_ch[1].
  - Each channel handles both conditional and indirect resolution.

When dual_pred_en=0:
  - One prediction slot active.
  - One update channel: upd_ch[0] only.

---

## History Module

Centralized ownership of all branch history state. Owned by BPC,
not rename/dispatch. No SRAM -- purely registered state.

### Registers

GHR (Global History Register):
  Width:  GHR_WIDTH = 256b circular buffer
  Pointer: ghist_ptr (GHIST_PTR_BITS = 8b), driven externally
  Update: speculative on each prediction. Write pred_taken into
          buffer at ghist_ptr position, one write per active
          prediction slot in priority order.
  Restore: on redirect, accept new ghist_ptr from external logic.
           Recompute all folded histories from buffer contents.

PHR (Path History Register):
  Width:  PHR_WIDTH = 32b circular buffer
  Pointer: phist_ptr (PHIST_PTR_BITS = 5b), driven externally
  Update: speculative on each prediction:
            PHR[phist_ptr] = pred_pc[2] ^ pred_pc[3]
          One write per active prediction slot in priority order.
          Bit selection (pc[2] ^ pc[3]) is subject to tuning.
  Restore: on redirect, accept new phist_ptr from external logic.
           Same policy as GHR.

PHR folding is deferred. bp_history.sv maintains phr_mem and
exposes phr_buf, but PHR does not contribute to any fold in
bp_folded_hist_t. All current folds are GHR-derived only.
PHR contribution to index and tag hashing is TBD -- resolved
at TAGE and ITTAGE implementation sessions.

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

PHR/GHR mixing for index and tag hashing is TBD -- resolved
at TAGE and ITTAGE implementation sessions.

### Checkpoints

One checkpoint slot per FTQ entry (FTQ_DEPTH = 64 slots).
Each slot stores: ghist_ptr (8b) and phist_ptr (5b) only.
Folded histories are NOT checkpointed -- recomputed on rollback.
Implemented as register arrays indexed by FTQ_IDX_BITS.
Checkpoint written with post-update pointer values.

---

## Update Policy

Update trigger: post-execute resolution. No wait for retire.
Two update channels when dual_pred_en=1, one when dual_pred_en=0.
Each channel carries both conditional and indirect branch resolution
(they are one combined channel, not split by type).

RAS update: speculative at s2 (separate from main update channels).
Checkpoint/restore: RAS speculative state must be checkpointed and
restored on mispredict flush. Policy TBD at rename/dispatch.

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
  SC_NUM_MAIN_TBLS   = 4                  (ST0-ST3)
  SC_NUM_ALL_TBLS    = 5                  (ST0-ST4 including IMLI)
  FTQ_CONF_BITS      = 4                  (confidence placeholder)

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

Verilator does not provide timing data. Pipe stage notation in struct
comments (P0.comb, P1.clk) expresses intent to Claude Code but is not
verified by any automated tool. Jeff reviews RTL directly for timing
correctness. This is documented as a known methodology gap.

Timing intent for BP cluster structs uses s-stage notation to match
the prediction pipeline rather than P-stage notation from the decoder:
  s0.comb = combinational in s0
  s1.clk  = registered at end of s1 (available start of s2)
  etc.

---

## Methodology Notes

This is the second case study for the AI-assisted co-design methodology
writeup. Complexity drivers vs. the decoder track:
  - Micro-architectural decisions were open (not spec-driven)
  - Interfaces not predetermined by any external spec
  - Multi-module consistency is a real challenge (6 predictor modules
    plus cluster top, all sharing bp_pkg.sv structs)
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

