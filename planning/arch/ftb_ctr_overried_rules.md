<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Confidence Override Rules
```
 FILE:    planning/arch/ftb_ctr_override_rules.md
 SOURCE:  ftb_decision_record.md (session-051)
 STATUS:  COMPLETE
 UPDATED: 2026-06-24
 CONTACT: Jeff Nye
```

Policy document for the FTB per-branch confidence counter (CTR) and its
role in suppressing TAGE/SC direction overrides. Canonical authority
is ftb_decisions.md. This document governs the confidence mechanism
only.

No TAGE analog: this policy is new to FTB. Do not copy TAGE or ITTAGE
USE/UAON update tables as templates -- the counter purpose and trigger
conditions are different.

---

## 1. Purpose

The confidence counter (CTR) measures FTB's per-branch direction accuracy
over time. When confidence is sufficiently high, FTB's direction
prediction suppresses a TAGE/SC direction override for that branch,
avoiding the redirect bubble the override would cause. This is a
performance mechanism: avoid the redirect bubble when the fast
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

  conf[2:0]     3-bit saturating counter per conditional branch field.
                Range 0 (lowest confidence) to 7 (highest confidence).
                One conf field per conditional branch slot (br0, br1).
                Two conf fields per FTB entry.

---

## 3. Training Rules (C2, C9)

### 3.1 Train at execute; train only on resolved branches (C9)

Training fires when a conditional branch resolves at execute. A
branch resolves when its direction is determined by the execution
unit.

On a slot-0-taken cycle, slot 1's block is never executed (F2). No
resolved direction exists for slot 1. Do not train on discarded
slot-1 reads. Train on resolution, not on read.

### 3.2 Training is unconditional on FTB correctness (C2)

At execute, for a resolved conditional branch:
  - if ftb_pred_dir == resolved_dir: increment conf (saturating at 7)
  - if ftb_pred_dir != resolved_dir: decrement conf (saturating at 0)

ftb_pred_dir: FTB's direction prediction for this branch, carried
in the FTQ entry for the block.
resolved_dir: the actual branch outcome from the execution unit.

Training is independent of whether FTB's output was used or caused
a redirect. The counter is a pure observer of "is FTB right about
this branch."

Rationale: if training were gated on FTB's prediction being used,
the counter would have a blind spot exactly where TAGE keeps
overriding FTB -- conf would never move and suppression would be
unreachable for the branches that need it. Unconditional training
has no feedback loop. Execute already has resolved_dir; ftb_pred_dir
is carried in the FTQ entry. No new information path required.

### 3.3 Training runs under the chicken bit (C6)

The chicken bit gates suppression (acting) only. Training always
runs, even when the chicken bit is off. See section 5.

### 3.4 Training runs even when always_taken is set (C5 extension)

always_taken takes priority over suppression, but does not disable
training. conf still increments or decrements based on FTB
correctness while always_taken is set. The counter is harmless
during always_taken (it does not act when always_taken=1), but
keeping it current means it is at the right value when always_taken
clears.

---

## 4. Acting Rules (C3, C4, C5)

### 4.1 Suppress direction overrides at s2, not target overrides (C3)

When at s2, for a given conditional branch:
  if (ftb_valid AND br_valid AND always_taken == 0
      AND conf >= FTB_CONF_SUPPRESS_THRESH
      AND chicken_bit_enable):
    suppress TAGE/SC direction override for this branch.
    FTB's direction stands. No redirect bubble.

Direction only. Target overrides (ITTAGE, RAS) are never suppressed.

The priority for direction becomes:
  "SC > TAGE > FTB ... unless FTB is confident"
Every downstream integration that applies a TAGE/SC direction
override must account for the suppression output.

The suppression output is ftb_suppress_dir_p2[slot][branch].
See ftb_interfaces.md section 2.4.

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
  - Training still runs. Conf counters continue to accumulate.

When chicken_bit_enable = 1:
  - Suppression is active per the rules in section 4.

The chicken bit gates the confidence suppression path only. It does
not gate always_taken. Under chicken_bit_enable=0, always_taken
still suppresses the direction predictor. Do not let documentation
or RTL make the chicken bit disable always_taken.

---

## 6. Parameters

  FTB_CONF_SUPPRESS_THRESH    Suppression threshold. Default 6
                              (top two states of 0-7). Parameterized
                              for sweep; not baked at a specific value.

  FTB_CONF_INIT               Reset value on allocation. Default
                              3'b011 (= 3). Parameterized.

  Invariant (must assert in RTL and testbench):
    FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH
    A fresh entry must start below threshold. If init >= thresh,
    fresh entries suppress immediately, defeating the training gate.

Add to bp_defines_pkg.sv at RTL task time.

---

## 7. Reset and Allocation Behavior (C8)

On entry allocation, conf[2:0] for each conditional branch field
resets to FTB_CONF_INIT. This prevents a reallocated entry from
carrying a previous branch's confidence.

A fresh entry starts below FTB_CONF_SUPPRESS_THRESH and must earn
its way to suppression through confirmed correctness.

---

## 8. Interaction Summary

| Condition                        | Direction prediction source   |
|----------------------------------|-------------------------------|
| FTB miss (ftb_valid=0)           | Upstream (uBTB / loop pred)   |
| FTB hit, always_taken=1          | FTB (always taken)            |
| FTB hit, conf >= thresh, ck=1    | FTB (suppression active)      |
| FTB hit, conf >= thresh, ck=0    | TAGE/SC (suppression off)     |
| FTB hit, conf < thresh           | TAGE/SC (override applies)    |

Target prediction source is never affected by this table. ITTAGE
and RAS target overrides proceed independently.

---

## 9. Verification Notes

Tests must cover:
  - conf increments on correct FTB predictions; saturates at 7.
  - conf decrements on incorrect FTB predictions; saturates at 0.
  - Training fires even when TAGE/SC override is applied.
  - Training fires even when always_taken=1.
  - Suppression fires only when conf >= FTB_CONF_SUPPRESS_THRESH
    AND chicken_bit_enable=1 AND always_taken=0 AND br_valid AND
    ftb_valid.
  - Suppression does not fire when chicken_bit_enable=0, even when
    conf is at maximum.
  - Suppression does not fire when always_taken=1, even when conf
    is at maximum.
  - Fresh entry after allocation starts at FTB_CONF_INIT, below
    suppress threshold.
  - Reallocation resets conf; previous branch's conf is not carried.
  - Slot-1 conf does not train on slot-0-taken cycles (C9).
  - Target overrides (ITTAGE, RAS) are not suppressed at any conf
    value.
  - Invariant FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH asserts.

---

## 10. Open Items

  - Confidence-override interaction with TAGE update/meta path:
    flagged, not yet analyzed. Resolve at bp_cluster integration.
  - chicken_bit_enable source: CSR, static tie, or runtime signal.
    TBD at bp_cluster integration.

