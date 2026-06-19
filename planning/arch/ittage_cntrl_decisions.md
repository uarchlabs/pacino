<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# ittage_cntrl Design Decisions
```
 FILE:    ittage_cntrl_decisions.md
 SOURCE:  various
 STATUS:  DRAFT, modified by hand
 UPDATED: 2026-05-16
 CONTACT: Jeff Nye
```

---

## Scope

This document captures settled design decisions for ittage_cntrl.sv.
It is a companion to ittage_interfaces.md and
ittage_table_interfaces.md. It does not restate information already
in those documents unless a decision modifies or extends them.

---

## Dual Prediction Support

ittage_cntrl supports two simultaneous prediction requests via
vector-indexed ports sized to NUM_PRED_SLOTS. Slot 0 and slot 1
operate identically and independently -- there is no cross-slot
interaction in prediction logic, update logic, or UAON counter
state. Both slots may have ittage_pred_val_p0 asserted in the same
cycle. Each slot has its own uaon counter (uaon[0], uaon[1]) and
aging interval counter (lcl_aging_interval[0],
lcl_aging_interval[1]).
Provider selection, alternate provider selection, UAON mux, and
ittage_pred_meta population are replicated per slot. Slot 1 PC is
supplied by the fetch unit via ittage_pred_inp_p0[1].pc. No offset
derivation is performed in ittage_cntrl.

---

## No Base Table

ITTAGE has no IT0 base table. Unlike TAGE there is no unconditional
fallback provider. When no IT1-IT5 table hits, ittage_hit is
de-asserted in the response and the consumer uses the FTB target.
ittage_pred_rdy_p2 is still asserted -- the response is valid even
when ittage_hit == 0. There is no equivalent of T0 behavior,
T0 CTR encoding, or T0 direction output. All rows in the CTR update
table that reference comp==0 map to no-hit, not a base table.

---

## CTR Encoding (IT1-IT5, 3b)

CTR is a confidence counter. It does not encode direction.

  000  null    no confidence (target replacement candidate)
  001  low1    low confidence
  010  low2    low confidence
  011  low3    low confidence (boundary -- UAON trigger point)
  100  high0   high confidence (boundary -- UAON trigger point)
  101  high1   high confidence
  110  high2   high confidence
  111  high3   maximum confidence

Direction = not applicable. ITTAGE predicts target address only.

Strong states: 000 (null), 111 (maximum confidence).
Weak states: 001, 010, 011, 100, 101, 110.
Boundary states: 011 and 100 -- UAON trigger points.

Newly allocated entries initialize to 3'b000 (null confidence).

---

## use_alt_on_na Counters

Two 4b saturating counters (IT_UAON_WIDTH=4), one per prediction
slot. Both owned by ittage_cntrl. Both operate independently.
No cross-slot interaction in prediction or update.
Initial value: IT_UAON_THRES=8.

Trigger condition: provider CTR is 3'b000 (null) only.
  Expressed as: (ctr == 3'b000)

ittage_use_alt_on_na captures the trigger decision into meta.
Counter state at predict time is not stored in meta. Only the
single-bit trigger decision (ittage_use_alt_on_na) is captured.

For mux selection logic and counter update rules see
ittage_cntrl_uaon_update_rules.md.

---

## Prediction Phase -- ittage_cntrl Responsibilities

### Provider selection (p1, combinational)

Scan IT5 down to IT1 for hit_p1[slot] asserted.
Longest history hit wins -- this is the primary provider.
If no tagged table hits: ittage_hit de-asserted in response.
ittage_pred_rdy_p2 still asserts. No fallback base table.

Captures into meta:
  ittage_prm_idx     -- already-hashed RAM index of primary hit
  ittage_prm_comp    -- table index of primary provider
  ittage_prm_useful  -- useful field of primary provider entry
  ittage_prm_ctr     -- CTR field of primary provider entry
  ittage_prm_tgt    -- target from primary provider entry

### Alternate provider (p1, combinational)

Continue scan below primary hit for next longest hit.
If primary is IT1 or ittage_hit == 0, alternate is absent
(ittage_alt_comp == 0).

Captures into meta:
  ittage_alt_idx     -- already-hashed RAM index of alternate
  ittage_alt_comp    -- table index of alternate provider
  ittage_alt_useful  -- useful field of alternate provider entry
  ittage_alt_ctr     -- CTR field of alternate provider entry
  ittage_alt_tgt     -- target from alternate provider entry

### Allocation candidate (p1, combinational)

See ittage_cntrl_alloc_rules.md for full rules.

ittage_cntrl generates ittage_alc_idx directly (pre-hashed).
Source is the idx_hash_p0 that was used to access the candidate
table during prediction. Written into meta as-is. Update path
uses it as a direct RAM address with no rehashing.

Captures into meta:
  ittage_alc_comp  -- table index of allocation candidate
  ittage_alc_idx   -- pre-hashed RAM index of candidate
  ittage_alc_tag   -- tag captured at predict time

### Decoration flags (p1, combinational)

  ittage_pred_strong   -- provider ctr was != 0
  ittage_use_alt_on_na -- use_alt_on_na was used to select
  ittage_using_primary -- provider was primary, else alternate
  ittage_hit           -- at least one IT1-IT5 table hit
  branch_id            -- copied from ittage_pred_inp_t

### Final target (p1, combinational)

ittage_cntrl does not pick a single predicted target. It
captures both candidate targets and the selector into meta and
leaves the choice to the consumer:

ittage_prm_tgt       -- target from primary provider entry
ittage_alt_tgt       -- target from alternate provider entry
ittage_using_primary -- selector: 1 = primary, 0 = alternate

The consumer selects:
ittage_using_primary == 1 -> ittage_prm_tgt
ittage_using_primary == 0 -> ittage_alt_tgt

ittage_using_primary is set during provider selection (p1):
primary when ittage_prm_ctr != 3'b000; on null primary CTR,
alternate when use_alt_on_na fired (UAON counter >=
IT_UAON_THRES), else primary. See ittage_cntrl_uaon_update_rules.md
for the mux rule.

When ittage_hit == 0 there is no provider target; the consumer
uses the FTB target. ittage_pred_rdy_p2 still asserts.

All meta fields are flopped at p2 (see p2 flop). The selection
above is performed by the consumer on the p2 meta.

### p2 flop

All meta fields flopped at p2.
These are packed into the ittage_pred_meta_t struct.

ittage_pred_rdy flopped alongside, gated on ittage_pred_val_p0
delayed one cycle.

---

## CTR Update Rules

See ittage_cntrl_ctr_update_rules.md for the full table.

Summary of cases:
- prm_comp > 0 and alt_comp > 0: both providers are tagged
  tables. CTR actions per rows 2-5 of update table.
- prm_comp == 0 and alt_comp == 0: no hit. No CTR update.
  Allocation path only. Row 1.
- prm_comp > 0 and alt_comp == 0: primary hit, no alternate.
  Only primary CTR updated. Rows 6-9.
- prm_comp == 0 and alt_comp > 0: unreachable.

---

## Target Update Rules

Target field write gating is defined in ittage_interfaces.md
§Target Write Gating.

---

## Useful Counter and Aging Rules

See ittage_cntrl_use_update_rules.md.
Key difference from TAGE: useful counter governs allocation
candidate eligibility. Aging and UAON interaction follow the
same principles as TAGE unless noted otherwise.

---

## Allocation Rules

See ittage_cntrl_alloc_rules.md for full rules.

---

## Concurrent CTR and USE Writes

When the CTR update rules and the useful update rules both
target the same table and same index in the same cycle, the
two writes are performed as a single RAM write.

ittage_cntrl must combine the active write enables and align
both the CTR write data and the USE write data into a single
ram_din word. The bweb_n mask must have bits cleared for both
the CTR field range and the USE field range simultaneously.

This is structurally supported by bw_ram and the existing
bweb_n logic in ittage_table.sv. ittage_cntrl is responsible
for asserting both strobes in the same cycle with correctly
aligned data. ittage_table performs the merged write.

---

## Concurrent CTR and TGT Writes

It is the intent expressed by Seznec that the target field is only
replaced during a misprediction if the corresponding CTR is 0. 

On misprediction if the CTR is 0 the target field is written;
if the CTR is non-zero, the CTR is decremented, the target
field is not written.

Previously, the CTR and TGT writes were required to be mutually
exclusive. This is unnecessarily restrictive. 

---

## Open Items

1. CLOSED session-036: ittage_table_interfaces.md created.

2. CLOSED session-037: II6 tgt_wr_u0 gating defined.
   See ittage_interfaces.md Target Write Gating section.

