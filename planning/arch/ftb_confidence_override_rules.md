<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Confidence Override Rules
```
 FILE:    planning/arch/ftb_confidence_override_rules.md
 SOURCE:  ftb_decision_record.md (session-051), ftb_decisions.md,
          ftb_interfaces.md
 STATUS:  DRAFT
 UPDATED: 2026-06-24
 CONTACT: Jeff Nye
```

Policy document for the FTB per-branch confidence counter (conf) and
its role in suppressing TAGE/SC direction overrides. Canonical
authority is ftb_decisions.md. This document governs the confidence
mechanism only.

No TAGE analog: this policy is new to FTB. Do not copy TAGE or ITTAGE
USE/UAON update tables as templates -- the counter purpose and trigger
conditions are different.

Single-array reminder: FTB is one array, one lookup per cycle, one
entry per block. The two conditional fields br0 and br1 both come from
that one entry (ftb_decisions.md 2.1). There are no per-slot lookups.
This document refers to br0 and br1, never to slot-0 / slot-1.

---

## 1. Purpose

The confidence counter (conf) measures FTB's per-branch direction
accuracy over time. When confidence is sufficiently high, FTB's
direction prediction suppresses a TAGE/SC direction override for that
branch, avoiding the redirect bubble the override would cause. This is
a performance mechanism: avoid the redirect bubble when the fast
predictor is reliably right.

Confidence interacts with two other override mechanisms:
  - always_taken: takes priority over confidence (C5). If always_taken
    is set, the direction predictor is bypassed entirely; the
    confidence path is not consulted for that branch.
  - TAGE/SC direction override: suppressed by confidence when
    conf >= FTB_CONF_SUPPRESS_THRESH and the chicken bit is enabled.

Confidence never suppresses TARGET overrides. ITTAGE and RAS target
overrides are never affected by the confidence counter.

---

## 2. Counter Structure (C1)

  conf[FTB_CONF_WIDTH-1:0]   3-bit saturating counter (FTB_CONF_WIDTH
                = 3) per conditional branch field. Range 0 (lowest
                confidence) to 7 (highest confidence). One conf field
                per conditional branch field (br0, br1). Two conf
                fields per FTB entry.

The conf value for each branch is exposed at s2 on ftb_br0_conf_p2 /
ftb_br1_conf_p2 (ftb_interfaces.md 2.3).

---

## 3. Training Rules (C2, C9)

### 3.1 Train at execute; train only on resolved branches (C9)

Training fires when a conditional branch resolves at execute. A branch
resolves when its direction is determined by the execution unit.

A single FTB entry holds two conditional fields, br0 and br1. The
executed path may not reach both. If control leaves the block before a
conditional field is reached -- the earlier branch redirects away, or
the terminal jump fires first -- that field's branch is never executed
and has no resolved direction. Do not train a conditional field that
was read in the prediction but not reached on the executed path. Train
on resolution, not on read.

This is per-field: br0 and br1 train independently, each only when its
own branch resolves. There is no slot-1 lookup to discard -- both
fields are part of the one indexed entry (ftb_decisions.md 2.1,
section 3).

### 3.2 Training is unconditional on FTB correctness (C2)

At execute, for a resolved conditional branch:
  - if ftb_upd_ftb_dir_u0 == ftb_upd_taken_u0: increment conf
    (saturating at 7)
  - if ftb_upd_ftb_dir_u0 != ftb_upd_taken_u0: decrement conf
    (saturating at 0)

ftb_upd_ftb_dir_u0: FTB's original direction prediction for this
branch, carried in the FTQ entry and presented on the update port
(ftb_interfaces.md 2.5).
ftb_upd_taken_u0: the resolved branch outcome from the execution unit,
on the update port.

Training is independent of whether FTB's output was used or caused a
redirect. The counter is a pure observer of "is FTB right about this
branch."

Rationale: if training were gated on FTB's prediction being used, the
counter would have a blind spot exactly where TAGE keeps overriding
FTB -- conf would never move and suppression would be unreachable for
the branches that need it. Unconditional training has no feedback
loop. Execute already has the resolved direction; FTB's original
prediction is carried in the FTQ entry. No new information path
required.

### 3.3 Training runs under the chicken bit (C6)

The chicken bit gates suppression (acting) only. Training always runs,
even when the chicken bit is off. See section 5.

### 3.4 Training runs even when always_taken is set (C5 extension)

always_taken takes priority over suppression, but does not disable
training. conf still increments or decrements based on FTB correctness
while always_taken is set. The counter is harmless during always_taken
(it does not act when always_taken=1), but keeping it current means it
is at the right value when always_taken clears.

---

## 4. Acting Rules (C3, C4, C5)

### 4.1 Suppress direction overrides at s2, not target overrides (C3)

At s2, for each conditional branch i in {0 = br0, 1 = br1}:
  if (ftb_valid_p2 AND ftb_brI_valid_p2 AND always_taken == 0
      AND conf >= FTB_CONF_SUPPRESS_THRESH
      AND chicken_bit_enable):
    suppress the TAGE/SC direction override for branch i.
    FTB's direction stands. No redirect bubble.

Direction only. Target overrides (ITTAGE, RAS) are never suppressed.

The priority for direction becomes:
  "SC > TAGE > FTB ... unless FTB is confident"
Every downstream integration that applies a TAGE/SC direction override
must account for the suppression output.

The suppression output is ftb_suppress_dir_p2, a 2-bit vector: bit 0 =
br0, bit 1 = br1 (ftb_interfaces.md 2.4). There is no slot dimension;
the two bits are the two conditional fields of the one entry.

### 4.2 always_taken has priority over confidence (C5)

If always_taken is set for a conditional branch:
  - Use always_taken=1 as the direction. Branch is predicted taken.
  - Do not consult the confidence counter for this branch.
  - The direction predictor (TAGE/SC) is already bypassed.
  - The confidence counter still trains (section 3.4).

always_taken=1 and conf>=thresh are two independent reasons FTB
direction can stand. always_taken is checked first.

### 4.3 Acting and training are asymmetric (C4)

The counter trains unconditionally at every execute resolution (C2)
but acts only selectively:
  - only at s2
  - only when conf >= FTB_CONF_SUPPRESS_THRESH
  - only for direction overrides, not target overrides
  - only when the chicken bit is enabled

Both contracts must be stated when documenting this field. A reader
seeing only suppression wonders how conf got high. A reader seeing
only training does not know it gates anything.

---

## 5. Chicken Bit (C6)

  chicken_bit_enable    1-bit global enable for confidence suppression.

When chicken_bit_enable = 0:
  - Suppression is disabled. TAGE/SC direction overrides proceed
    unconditionally.
  - Training still runs. conf counters continue to accumulate.

When chicken_bit_enable = 1:
  - Suppression is active per the rules in section 4.

The chicken bit gates the confidence suppression path only. It does
not gate always_taken. Under chicken_bit_enable=0, always_taken still
suppresses the direction predictor. Do not let documentation or RTL
make the chicken bit disable always_taken.

---

## 6. Parameters

  FTB_CONF_WIDTH              Counter width. 3 bits (range 0-7).

  FTB_CONF_SUPPRESS_THRESH    Suppression threshold. Default 6 (top
                              two states of 0-7). Parameterized for
                              sweep; not baked at a specific value.

  FTB_CONF_INIT               Reset value on allocation. Default
                              3'b011 (= 3). Parameterized.

  Invariant (must assert in RTL and testbench):
    FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH
    A fresh entry must start below threshold. If init >= thresh, fresh
    entries suppress immediately, defeating the training gate.

Add to bp_defines_pkg.sv at RTL task time (ftb_decisions.md 8).

---

## 7. Reset and Allocation Behavior (C8)

On entry allocation, conf for each conditional branch field resets to
FTB_CONF_INIT. This prevents a reallocated entry from carrying a
previous branch's confidence.

A fresh entry starts below FTB_CONF_SUPPRESS_THRESH and must earn its
way to suppression through confirmed correctness.

---

## 8. Interaction Summary

| Condition                          | Direction prediction source |
|------------------------------------|-----------------------------|
| FTB miss (ftb_valid_p2=0)          | Upstream (uBTB / loop pred) |
| FTB hit, always_taken=1            | FTB (always taken)          |
| FTB hit, conf >= thresh, ck=1      | FTB (suppression active)    |
| FTB hit, conf >= thresh, ck=0      | TAGE/SC (suppression off)   |
| FTB hit, conf < thresh             | TAGE/SC (override applies)  |

ck = chicken_bit_enable. The table is per conditional branch (br0 and
br1 evaluate independently). Target prediction source is never
affected by this table; ITTAGE and RAS target overrides proceed
independently.

---

## 9. Verification Notes

Tests must cover:
  - conf increments on correct FTB predictions; saturates at 7.
  - conf decrements on incorrect FTB predictions; saturates at 0.
  - Training fires even when a TAGE/SC override is applied.
  - Training fires even when always_taken=1.
  - Suppression fires only when conf >= FTB_CONF_SUPPRESS_THRESH
    AND chicken_bit_enable=1 AND always_taken=0 AND ftb_brI_valid_p2
    AND ftb_valid_p2.
  - Suppression does not fire when chicken_bit_enable=0, even when
    conf is at maximum.
  - Suppression does not fire when always_taken=1, even when conf is
    at maximum.
  - Fresh entry after allocation starts at FTB_CONF_INIT, below the
    suppress threshold.
  - Reallocation resets conf; the previous branch's conf is not
    carried.
  - A conditional field (br0 or br1) does not train when its branch is
    not reached on the executed path (C9).
  - br0 and br1 train independently, each only on its own resolution.
  - Target overrides (ITTAGE, RAS) are not suppressed at any conf
    value.
  - Invariant FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH asserts.

---

## 10. Open Items

  - Confidence-override interaction with the TAGE update/meta path:
    flagged, not yet analyzed. Resolve at bp_cluster integration
    (ftb_decisions.md FTB-2).
  - chicken_bit_enable source: CSR, static tie, or runtime signal.
    TBD at bp_cluster integration.

---

## 11. Document History

  2026-06-24  session-052. Regenerated from the session-051 draft,
              which was authored before the single-array correction
              and carried the rejected slot-0 / slot-1 model.
              Corrections: file renamed from ftb_ctr_override_rules.md
              to ftb_confidence_override_rules.md (matches the two
              companion docs); slot-0/slot-1 framing removed and C9
              re-expressed per conditional field (br0/br1) of the one
              entry; suppression output corrected to the 2-bit
              ftb_suppress_dir_p2 (bit 0 br0, bit 1 br1, no slot
              dimension) matching ftb_interfaces.md 2.4; training
              signals named ftb_upd_ftb_dir_u0 / ftb_upd_taken_u0 and
              valid signals named ftb_valid_p2 / ftb_brI_valid_p2 to
              match the interface; STATUS demoted COMPLETE -> DRAFT
              (open items remain). Parameters, training/acting
              rationale, chicken-bit semantics, always_taken priority,
              reset-on-allocate, interaction table, and verification
              list carried forward unchanged where already aligned.

