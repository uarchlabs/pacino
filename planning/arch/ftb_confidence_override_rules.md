<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Confidence Direction and Fast-Path Rules
```
 FILE:    planning/arch/ftb_confidence_override_rules.md
 SOURCE:  session-051/052/053
 STATUS:  DRAFT
 UPDATED: 2026-06-25
 CONTACT: Jeff Nye
```

Policy document for the FTB per-branch confidence counter (conf) and
its role as a bimodal DIRECTION predictor plus the fast-path that lets
a high-certainty FTB direction skip the TAGE/SC wait. Canonical
authority is ftb_decisions.md. This document governs the conf mechanism
only.

Single-array reminder: FTB is one data array, one lookup per cycle, one
entry per block. The two conditional fields br0 and br1 both come from
that one entry (ftb_decisions.md 2.1). This document refers to br0 and
br1, never to slot-0 / slot-1.

Field note: the entry no longer carries an always_taken bit -- it was
removed (session-053). conf is the sole per-branch direction state.

---

## 1. Purpose

conf is a per-branch BIMODAL DIRECTION counter. Its MSB is FTB's
predicted direction for that conditional; its magnitude is the strength
of that prediction. FTB always submits a direction for every valid
conditional.

When conf is SATURATED (all-ones or all-zeros) and the fast-path is
enabled, FTB commits its own direction at s2 and does NOT wait for
TAGE/SC, ignoring any TAGE/SC direction difference for that branch.
This saves the cycle that waiting for the s3 SC response would cost
(ftb_decisions.md 1.1). When conf is not saturated, or the fast-path is
disabled, FTB waits for TAGE/SC and is overridden as normal -- ordinary
BTB-like behavior.

conf never affects TARGET overrides. ITTAGE and RAS target overrides
are independent of this mechanism.

---

## 2. Counter Structure (C1)

  conf[FTB_CONF_WIDTH-1:0]   3-bit saturating bimodal counter
                (FTB_CONF_WIDTH = 3) per conditional branch field.
                States 000 (strongly not-taken) .. 111 (strongly
                taken). One conf field per conditional field (br0,
                br1); two conf fields per entry.

  Direction  = conf[FTB_CONF_WIDTH-1]   (the MSB).
               1 = predict taken, 0 = predict not-taken.
  Strength   = distance from the midpoint. 111 / 000 are the two
               saturated (maximum-certainty) states.

conf is exposed at s2 on ftb_br0_conf_p2 / ftb_br1_conf_p2
(ftb_interfaces.md 2.3).

---

## 3. Direction and Training (C2, C9)

### 3.1 FTB direction is the conf MSB

For a valid conditional, FTB's predicted direction is the conf MSB:

  ftb_brI_taken_p2 = ftb_brI_valid_p2 & conf_brI[FTB_CONF_WIDTH-1]

This is FTB's submitted direction whether or not the fast-path fires.

### 3.2 Train at execute; bimodal toward the resolved outcome (C9)

Training fires when a conditional branch resolves at execute, per field
br0/br1 INDEPENDENTLY, each only when its own branch resolves. A field
read in the prediction but not reached on the executed path does not
train (control left the block first).

The update is the conventional bimodal counter step, driven by the
RESOLVED OUTCOME (ftb_upd_taken_u0), saturating:

  resolved taken     : conf = (conf == '1) ? conf : conf + 1
  resolved not-taken : conf = (conf == '0) ? conf : conf - 1

Training is on the OUTCOME, not on whether FTB's prediction was used or
was correct. No ftb_upd_ftb_dir_u0 input is required (removed). The
counter is a pure bimodal observer of the branch's direction history.

### 3.3 Training is independent of the fast-path and of TAGE/SC use

conf trains on every resolution regardless of ftb_fastpath_en and
regardless of whether the fast-path fired or TAGE/SC overrode. This is
what makes the fast-path self-correcting (3.4).

### 3.4 Self-correction at the saturated endpoints

A saturated entry that mispredicts steps OUT of saturation on that
resolve (111 -> 110 on a not-taken outcome, 000 -> 001 on a taken
outcome). The fast-path (section 4) then stops firing for that branch
until conf re-saturates. A single wrong outcome ends the fast-path
eligibility; the branch must re-earn saturation. This bounds the cost
of a wrong fast-path commit to its own misprediction plus recovery.

---

## 4. Fast-Path (C3, C4)

### 4.1 Condition

For each conditional branch i in {0 = br0, 1 = br1}, the fast-path
fires when:

  ftb_valid_p2 AND ftb_brI_valid_p2 AND ftb_fastpath_en
    AND (conf_brI == '1 OR conf_brI == '0)     -- saturated

The two saturated states are the only fast-path-eligible states. A
fresh or flapping entry is mid-range and never fast-paths (section 7).

### 4.2 Effect

When the fast-path fires for branch i:
  - FTB commits its own direction (conf MSB) at s2 for that branch.
  - FTB does NOT wait for the s3 SC response -- this is the saved cycle.
  - Any TAGE or SC DIRECTION difference for that branch is ignored; no
    TAGE/SC direction override is applied.
  - TARGET overrides (ITTAGE / RAS) are unaffected and proceed normally.

The fast-path output is ftb_fastpath_p2, a 2-bit vector: bit 0 = br0,
bit 1 = br1 (ftb_interfaces.md 2.4). It tells the cluster override logic
"FTB direction stands for this branch; do not apply a TAGE/SC direction
override and do not stall for SC."

### 4.3 Not firing

When ftb_fastpath_en = 0, or conf is not saturated, the fast-path does
not fire: FTB submits its direction (3.1) but waits for TAGE/SC and is
overridden as normal. The priority is the standard chain
SC > TAGE > FTB on direction.

---

## 5. ftb_fastpath_en (C6)

  ftb_fastpath_en   1-bit global enable for the fast-path.

  = 1 : fast-path active per section 4 (saturated conf may bypass the
        TAGE/SC wait/override).
  = 0 : fast-path disabled. FTB always waits for TAGE/SC and is
        overridable as normal -- FTB behaves as an ordinary BTB-like
        structure under the longer-history predictors.

Naming note: this is the inverse-sense of a classic "chicken bit." Here
the 1 state ENABLES the optimization (the bypass); the 0 state is the
safe, always-overridable mode. Source is TBD at bp_cluster integration
(CSR, static tie, or runtime). It gates the bypass only -- it does NOT
gate conf training (section 3.3) or TAGE/SC training (section 6).

---

## 6. TAGE/SC still requested and trained (C5)

Even when the fast-path fires and FTB ignores the TAGE/SC direction,
TAGE/SC are still REQUESTED for that branch and still UPDATED/trained
later. The fast-path suppresses the USE of the TAGE/SC direction, not
its prediction or its training. Skipping the training would let
TAGE/SC go cold exactly on the branches FTB currently fast-paths, so
they could never re-take a branch whose behavior changes.

This is a cluster/FTQ obligation: the override-resolution and update
paths must keep the TAGE/SC predict+update alive when FTB fast-paths.
Resolved at bp_cluster integration (ftb_decisions.md FTB-2).

---

## 7. Parameters and Reset/Allocation (C8)

  FTB_CONF_WIDTH      Counter width. 3 bits, states 0-7.

  FTB_CONF_INIT_TKN   Allocate value when the branch allocated TAKEN.
                      Default 3'b100 (weakly taken: MSB=1, unsaturated).
  FTB_CONF_INIT_NTK   Allocate value when the branch allocated
                      NOT-TAKEN. Default 3'b011 (weakly not-taken:
                      MSB=0, unsaturated).

On entry allocation, conf for the resolved conditional is set weak in
the OBSERVED direction:
  conf = ftb_upd_taken_u0 ? FTB_CONF_INIT_TKN : FTB_CONF_INIT_NTK
This carries the correct first direction (the MSB matches the observed
outcome) at minimum strength.

  Invariant (assert in RTL and tb):
    FTB_CONF_INIT_TKN is not saturated  (!= '1)   and MSB = 1
    FTB_CONF_INIT_NTK is not saturated  (!= '0)   and MSB = 0
  A fresh entry must start unsaturated so it cannot fast-path on first
  use; it must earn saturation through repeated same-direction
  outcomes.

There is no suppression threshold. The previous FTB_CONF_SUPPRESS_THRESH
parameter and the threshold-compare are removed; fast-path eligibility
is the two saturated endpoints only.

Reallocation overwrites conf with the weak init for the new branch's
observed direction, so a reallocated entry never carries the previous
branch's conf.

Add FTB_CONF_INIT_TKN / FTB_CONF_INIT_NTK to bp_defines_pkg.sv at RTL
task time (ftb_decisions.md 8).

---

## 8. Interaction Summary

| Condition                                   | Direction used      |
|---------------------------------------------|---------------------|
| FTB miss (ftb_valid_p2=0)                    | Upstream (uBTB/loop)|
| FTB hit, en=1, conf saturated (111 or 000)  | FTB (fast-path,     |
|                                             |  conf MSB, no wait) |
| FTB hit, en=1, conf not saturated           | TAGE/SC (override   |
|                                             |  as normal)         |
| FTB hit, en=0 (any conf)                    | TAGE/SC (override   |
|                                             |  as normal)         |

The table is per conditional branch (br0 and br1 evaluate
independently). FTB always SUBMITS a direction (conf MSB); the table is
about whose direction is USED. Target prediction source is never
affected; ITTAGE/RAS target overrides proceed independently.

---

## 9. Verification Notes

Tests must cover:
  - conf direction = MSB: predict taken when MSB=1, not-taken when
    MSB=0, for a valid conditional.
  - Bimodal training: taken outcome increments (saturates at 111),
    not-taken outcome decrements (saturates at 000).
  - Training fires on the outcome regardless of fast-path or whether
    TAGE/SC would override; per-field br0/br1 independence; a field not
    reached on the executed path does not train.
  - Self-correction: a saturated entry that mispredicts steps out of
    saturation (111->110, 000->001) and stops fast-pathing until it
    re-saturates.
  - Fast-path fires only when ftb_fastpath_en=1 AND conf saturated AND
    ftb_brI_valid_p2 AND ftb_valid_p2; ftb_fastpath_p2[i] asserted.
  - Fast-path does NOT fire when ftb_fastpath_en=0, even at a saturated
    conf.
  - Fast-path does NOT fire at an unsaturated conf, even with
    ftb_fastpath_en=1.
  - Allocate sets conf weak in the observed direction (TKN->100,
    NTK->011); a fresh entry does not fast-path on first use.
  - Reallocation resets conf to the new branch's weak init.
  - Target overrides (ITTAGE, RAS) are not affected at any conf value.
  - Invariants: FTB_CONF_INIT_TKN unsaturated with MSB=1;
    FTB_CONF_INIT_NTK unsaturated with MSB=0.

---

## 10. Open Items

  - Fast-path interaction with the TAGE update/meta path, and the
    obligation to keep TAGE/SC predict+update alive under fast-path
    (section 6): flagged, resolve at bp_cluster integration
    (ftb_decisions.md FTB-2).
  - ftb_fastpath_en source: CSR, static tie, or runtime signal. TBD at
    bp_cluster integration.
  - TD #80: conf hysteresis sweep. FTB_CONF_WIDTH is the knob if the
    3-bit bimodal hysteresis proves wrong under SPEC; widen, or disable
    the fast-path via ftb_fastpath_en. Width/policy sweep, not a
    format change.

---

## 11. Document History

  2026-06-24  session-052. Regenerated from the session-051 draft for
              the single-array correction (slot-0/slot-1 framing
              removed, ftb_suppress_dir_p2 2-bit output, signal names
              aligned, STATUS DRAFT).

  2026-06-25  session-053. Mechanism redefined. conf is now a BIMODAL
              DIRECTION counter (MSB = direction), not a one-directional
              confidence/suppression counter. always_taken removed (conf
              is the sole per-branch direction state). Threshold
              suppression replaced by a SATURATED-endpoint FAST-PATH:
              when ftb_fastpath_en=1 and conf is 111 or 000, FTB commits
              its direction at s2, skips the SC wait, and ignores TAGE/SC
              direction overrides for that branch (saving a cycle).
              FTB_CONF_SUPPRESS_THRESH removed. FTB_CONF_INIT split into
              FTB_CONF_INIT_TKN (3'b100) / FTB_CONF_INIT_NTK (3'b011),
              allocate weak-in-observed-direction. chicken_bit_enable
              renamed ftb_fastpath_en (inverse sense: 1 enables the
              bypass). ftb_suppress_dir_p2 output renamed ftb_fastpath_p2.
              Training is bimodal on the resolved outcome
              (ftb_upd_taken_u0); ftb_upd_ftb_dir_u0 input removed. TAGE/
              SC still requested and trained under fast-path (section 6).
              Self-correction at the endpoints added (3.4).

