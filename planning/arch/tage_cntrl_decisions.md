# tage_cntrl Design Decisions
```
 FILE:    tage_cntrl_decisions.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-05
 CONTACT: Jeff Nye
```

---

## Manual Changes Already Applied

The following changes have been applied manually to
bp_structs_pkg.sv before the BP-008 prompt is executed.
Claude Code must not re-apply or modify these.

  tage_pred_meta_t field renames:
    tage_pred_idx    -> tage_prm_idx
    tage_pred_comp   -> tage_prm_comp
    tage_pred_useful -> tage_prm_useful
    tage_pred_ctr    -> tage_prm_ctr

  tage_pred_meta_t fields added:
    tage_prm_tkn  -- direction from primary component CTR MSB
    tage_alt_tkn  -- direction from alternate component CTR MSB

---

## Scope

This document captures settled design decisions for tage_cntrl.sv
(BP-008). It is a companion to tage_interfaces.md and
tage_table_interfaces.md. It does not restate information already
in those documents unless a decision modifies or extends them.

---

## Dual Prediction Support

tage_cntrl supports two simultaneous prediction requests via
vector-indexed ports sized to NUM_PRED_SLOTS. Slot 0 and slot 1
operate identically and independently -- there is no cross-slot
interaction in prediction logic, update logic, or UAON counter
state. Both slots may have tage_pred_val_p0 asserted in the same
cycle. Each slot has its own uaon counter (uaon[0], uaon[1]) and
aging interval counter (lcl_aging_interval[0], lcl_aging_interval[1]).
Provider selection, alternate provider selection, UAON mux, and
tage_pred_meta population are replicated per slot. Slot 1 PC is
supplied by the fetch unit via tage_pred_inp_p0[1].pc. No offset
derivation is performed in tage_cntrl. tage_cntrl consumes
tage_pred_inp_p0[slot].pc[11:1] as the T0 RAM index for each slot
directly.

---

## T0 Behavior

T0 is the base table. It has no valid bit, no tag, no useful bit.
tage_cntrl treats T0 output as always-hit. T0 taken_p1 is
unconditionally valid as the fallback direction.

T0 uses a 2b saturating counter. Weak states are 01 and 10.
T0 initializes to 10 (weakest taken).

T0 is never the alternate provider -- it is always the fallback.
use_alt_on_na does not apply when T0 is the provider.

When use_alt_on_na fires and the alternate is T0, the direction
comes from T0 CTR MSB (bit 1).


T0 direction is always taken from the t_taken_p1[0][s] port
output of the T0 tage_table instance, not from the padded
CTR field in tage_pred_meta_t. t_taken_p1 is defined in
tage_table_interfaces.md as the MSB of the T0 entry, which
is CTR[1]. tage_prm_ctr stores the T0 2b CTR zero-padded
to 3b when T0 is provider. tage_prm_ctr[2] is always zero
for T0 and must never be used as the direction signal.
tage_prm_tkn captures the correct direction from
t_taken_p1[0][s] at predict time and is the authoritative
direction field for both prediction output and update-time
interpretation.

---

## CTR Encoding (T1-T4, 3b)

```
000  sn   not taken  strongly not taken
001  wn2  not taken  weakly not taken (less weak)
010  wn1  not taken  weakly not taken (just flipped)
011  wn0  not taken  weakest not taken
100  wt0  taken      weakest taken
101  wt1  taken      weakly taken
110  wt2  taken      weakly taken (less weak)
111  wt3  taken      strongly taken
```

Direction = CTR[2] (MSB).

Strong states: 000 (strongly NT), 111 (strongly T).
Weak states: 001, 010, 011 (weakly NT), 100, 101, 110 (weakly T).
Boundary states: 011 and 100 -- most uncertain, use_alt_on_na
trigger points.

Newly allocated entries initialize to 100 (weakest taken).

---

## use_alt_on_na Counters

Two 4b saturating counters, one per prediction slot.
Both owned by tage_cntrl. Both operate independently.
No cross-slot interaction in prediction or update.

Trigger condition: provider CTR is 3'b011 or 3'b100 only.
  Expressed as: (ctr == 3'b011) || (ctr == 3'b100)

When triggered and counter MSB is set: use alternate direction.
tage_using_primary reflects the final mux select.
tage_use_alt_on_na captures the trigger decision into meta.

Counter state at predict time is not stored in meta. Only the
single-bit trigger decision (tage_use_alt_on_na) is captured.

---

## Derived Signal

  pred_diff = tage_prm_tkn != tage_alt_tkn

pred_diff is not stored in meta. It is recomputed at update
time from tage_prm_tkn and tage_alt_tkn stored
in meta.

tage_pred_tkn remains the final output direction after
use_alt_on_na mux. It reflects tage_using_primary selection.

---

## Prediction Phase -- tage_cntrl Responsibilities

### Provider selection (p1, combinational)
Scan T4 down to T1 for hit_p1[slot] asserted.
Longest history hit wins -- this is the primary provider.
T0 is unconditional fallback if no tagged table hits.

Captures into meta:
  tage_prm_idx       -- already-hashed RAM index of primary hit
  tage_prm_comp      -- table index of primary provider
  tage_prm_useful    -- useful field of primary provider entry
  tage_prm_ctr       -- CTR field of primary provider entry
  tage_prm_tkn  -- CTR MSB of primary provider

### Alternate provider (p1, combinational)
Continue scan below primary hit for next longest hit.
If primary is T1 or T0 is provider, alternate is T0.

Captures into meta:
  tage_alt_idx       -- already-hashed RAM index of alternate hit
  tage_alt_comp      -- table index of alternate provider
  tage_alt_useful    -- useful field of alternate provider entry
  tage_alt_ctr       -- CTR field of alternate provider entry
  tage_alt_tkn  -- CTR MSB of alternate provider

### Allocation candidate (p1, combinational)
See tage_cntrl_alloc_rules.md for full rules.

tage_cntrl generates tage_alloc_idx directly (pre-hashed).
It is not run through tage_hash. Source is the index_hash_p0
that was used to access the candidate table during prediction.
Written into meta as-is. Update path uses it as a direct
RAM address with no rehashing.

Captures into meta:
  tage_alloc_comp  -- table index of allocation candidate
  tage_alloc_idx   -- pre-hashed RAM index of candidate
  tage_alloc_tag   -- tag captured at predict time

### Decoration flags (p1, combinational)

  tage_pred_strong;   -- provider ctr was !=3 and !=4
  tage_use_alt_on_na; -- use_alt_on_na was used to select provider
  tage_using_primary; -- provider was primary component, else alternative
  tage_high_conf;     -- provider was 3'b111 or 3'b000
  branch_id           -- copied from tage_pred_inp_t

### Final direction (p1, combinational)
Normally: tage_prm_tkn.
When use_alt_on_na fires (trigger condition met and counter
MSB set): tage_alt_tkn.
When alternate is T0: T0 CTR MSB (2b counter, bit 1).
Result -> tage_pred_tkn.

### p2 flop
All meta fields flopped at p2.
These are packed into the tage_pred_meta_t structs

tage_pred_rdy flopped alongside, gated on tage_pred_val_p0
delayed one cycle.

---

## CTR Update Rules

See tage_cntrl_ctr_update_rules.md for the full table.

resolved_taken is supplied at update time via tage_upd_inp_t.
pred_diff is recomputed at update from tage_prm_tkn and
tage_alt_tkn stored in meta.

Summary:
- prm_comp > 0 and alt_comp > 0: both providers are tagged
  tables. CTR actions per rows 1-12.
- prm_comp == 0 and alt_comp == 0: both are T0. T0 CTR
  updated per rows 13a-13d.
- prm_comp > 0 and alt_comp == 0: primary is tagged, alt
  is T0. Only primary CTR updated per rows 14-17.
  T0 not updated in these cases.
- prm_comp == 0 and alt_comp > 0: primary is T0, alt is
  tagged. Only alt CTR updated per rows 18-21.
  T0 not updated in these cases.

---

## Useful Counter and Aging Rules

See tage_cntrl_useful_update_rules.md for full rules
including UAON, Table 7, aging interval and epoch operation,
and u_eff computation.

---

## Allocation Rules

See tage_cntrl_alloc_rules.md for full rules.

---

## Concurrent CTR and USE Writes

When the CTR update rules and the useful update rules both
target the same table and same index in the same cycle,
the two writes are performed as a single RAM write.

tage_cntrl must combine the active write enables and align
both the CTR write data and the USE write data into a single
ram_din word. The bweb_n mask must have bits cleared for
both the CTR field range and the USE field range
simultaneously.

This is structurally supported by bw_ram and the existing
bweb_n logic in tage_table.sv. tage_cntrl is responsible
for asserting both strobes in the same cycle with correctly
aligned data. tage_table performs the merged write.

---

## Open Items Before BP-008 Prompt

1. tage_interfaces.md port list uses old field names. Must be
   updated to reflect tage_prm_* renames before or alongside
   BP-008. Assumed manual update.

