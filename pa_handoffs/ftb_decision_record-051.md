<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Decision Record -- session-051
```
 FILE:    ftb_decision_record-051.md
 SOURCE:  session-051 architecture discussion
 STATUS:  HANDOFF -- decisions only, not yet expanded to planning docs
 UPDATED: 2026-06-24
 CONTACT: Jeff Nye
```

Consolidated record of the FTB (Fetch Target Buffer) architectural
decisions made in pa session-051. This is the bridge artifact: it
captures the decisions and their rationale at full fidelity so a
fresh session can expand them into the formal planning documents
without needing the session-051 conversation.

Target planning documents to be produced from this record:
  - planning/arch/ftb_decisions.md            (decision record,
                                               canonical authority)
  - planning/interfaces/ftb_interfaces.md     (module interface
                                               contract)
  - planning/arch/ftb_confidence_override_rules.md
                                              (confidence-override
                                               policy; multi-predictor
                                               interaction, own doc)

Mirror the RAS pair (ras_decisions.md + ras_interfaces.md) for the
first two. The confidence doc has no RAS analog -- it is new.

Reference designs consulted this session: Xiangshan Kunminghu FTB
(the primary model), AMD Zen 2-5 BTB hierarchy (sizing data only),
Apple M2 (sizing anchor), Bray/Flynn Stanford BTB study (associativity
data). Divergences from Xiangshan are called out explicitly below --
this is NOT a straight port.

---

## 0. Context and Prior Constraints (already fixed, not decided here)

These were settled before session-051 and FTB must obey them:

- FTB lives at s2, alongside TAGE, ITTAGE, RAS.
- Override chain: SC > TAGE > FTB > uBTB. FTB overrides uBTB;
  TAGE/SC override FTB on direction; ITTAGE/RAS override FTB target.
- FTB is the branch-type classifier for the whole cluster. It tells
  RAS "this is a return", ITTAGE "this is an indirect", and supplies
  the fallthrough address. Three-way JALR split (FTB / RAS / ITTAGE)
  is resolved by FTB structural prediction before s2.
- FTB owns the fallthrough address RAS pushes (ras_fall_through_p2).
- NUM_PRED_SLOTS = 2. Fixed bundle split (G8): slot 0 = pred_pc+0:31,
  slot 1 = pred_pc+32:63. Slot 1 PC always pred_pc+32 (G17, static,
  not data-dependent on slot 0).
- TI6: banks are per-slot RAMs. RAM0 serves slot 0, RAM1 serves
  slot 1. Selection is structural.
- pacino expands RVC instructions to their 32b equivalents upstream.
  This changes the instruction granularity the FTB addresses -- see
  decision F12.
- ITTAGE has NO IT0 base table (bp_cluster.md). This is load-bearing
  for the FTB jump-slot target -- see decision F9.

---

## 1. Structural Decisions

### F1 -- Per-slot RAMs, no dual-port
FTB follows TI6. Two FTB RAMs, RAM0 -> slot 0, RAM1 -> slot 1, each
single-read. No dual-port array. Two independent block lookups per
cycle, one per slot-RAM.
Rationale: matches TAGE/ITTAGE convention; avoids 2R arrays; the
cost is paid in area (two RAMs) not port complexity.

### F2 -- Independent-blocks model
Each slot is its own FTB lookup producing its own prediction. Slot 1
always reads at pred_pc+32 (static per G17), regardless of slot 0's
outcome. Cross-slot taken-priority (if slot 0 has an earlier taken
branch, slot 1's block is not executed) is resolved DOWNSTREAM, not
in FTB. Slot 1 work is computed-then-discarded on slot-0-taken cycles.
Rationale: consistent with the fixed-boundary G8/G17 decision, which
already rejected data-dependent slot-1 start. Accepts wasted slot-1
work on slot-0-taken cycles as the cost of avoiding a serial
dependency.

### F3 -- Associativity: 4-way, parameterized
FTB_WAYS = 4 baseline. Parameterize so 8-way remains a synthesis-time
experiment, not a redesign.
Rationale: Xiangshan uses 4-way at the identical 2048-entry capacity
-- the strongest available data point, a working silicon decision at
our size. No public data quantifies the 4->8 way accuracy delta at
2048 entries; at that capacity conflict misses are already low and
associativity has diminishing returns. Commercial designs engineer
AROUND high associativity (compression, dynamic associativity), which
signals it is expensive, not free. 8-way was an unmeasured belief;
the burden of proof is on it. Circle back with own SPEC numbers if
time permits (revisit-trigger pattern, same as RAS stack depth).

### F4 -- Capacity: 2048 entries/slot baseline, parameterized
FTB_SETS parameterized. Baseline 2048 entries/slot = 512 sets x
4-way, PER SLOT (4096 entries total across both slots). Relief lever:
1024 entries/slot = 256 sets x 4-way, documented now as the
pre-authorized area/timing fallback (same pattern as RAS 16+32 ->
rebalance).
Sizing note: "2048" is PER SLOT, not total. State this explicitly in
the doc -- per-slot RAMs make "2048 entries" ambiguous and a silent
mis-read causes a doc-vs-RTL gap.
Rationale: commercial fast single-level BTBs cluster at 512-2048
TOTAL (Zen 2/3/4 fast L1 BTB = 512/1024/1536; Apple M2 ~2048;
Xiangshan FTB = 2048). 2048/slot is generous-but-defensible, slightly
aggressive; 1024/slot fallback lands exactly in the proven range.
The Zen 5 16K "L1 BTB" is NOT a counter-example -- it is the fast tier
of a DECOUPLED MULTI-LEVEL machine (16K L1 + 8K L2 victim), not one
flat array. Designs that go bigger go multi-level, not fatter-flat.

### F5 -- Growth path is multi-level, not fatter-flat
If 2048/slot proves insufficient under SPEC, the growth path is a
SECOND FTB level (L2 FTB, victim-cache style), consistent with the
already-decided decoupled frontend -- NOT a larger flat L1 FTB.
Rationale: matches how Zen scales BTB reach; consistent with
"BPU is decoupled frontend" already in bp_cluster.md.

### F6 -- Timing: FTB is off the zero-bubble path
uBTB is the zero-bubble s1 predictor providing the fast next-PC.
FTB at s2 is therefore not on the critical first-cycle path, which
loosens FTB's timing budget (it may be larger and slower-to-read).
FTB overrides uBTB at s2 on the larger-slower-more-accurate
presumption. That override is an s2 redirect WITH A BUBBLE -- this is
the designed cost that buys FTB its timing room. Document the bubble
explicitly as the consequence of the timing latitude, so a future
session sees WHY the latitude was safe.

---

## 2. Entry Format Decisions

### F7 -- 2+1 slot structure (three slots per entry)
Each FTB entry holds:
  - 2 conditional branch slots
  - 1 jump slot (terminal: unconditional jump / call / return)
NO Xiangshan-style slot sharing. The "two conditional branches in one
block, no jump" case fills both conditional slots directly.
Rationale: Xiangshan shares because they have only ONE dedicated
conditional slot and reuse the tail slot for a second conditional
(is_br_sharing flag). With two real conditional slots, sharing is
unnecessary -- simpler entry format, simpler update logic, no
is_br_sharing decode. Verification simplicity over area, consistent
with the project's prior calls (e.g. RAS two-real-slots over sharing).
Cost: always pay for two full conditional slots + a jump slot even in
the common one-branch block. Named, chosen tradeoff.
NOTE on project stance: Jeff will trade area for performance. Do NOT
optimize the entry toward minimum area at the expense of capability;
reducing complexity is welcome but giving up performance this early
is not.

### F8 -- Entry field list
Per entry:
  - valid                 -- entry valid
  - tag                   -- 4-way match tag. Width = upper PC bits
                             above the index. Index width from
                             FTB_SETS (512 sets -> 9 index bits).
                             Computed against the EXPANDED-instruction
                             block layout (see F12), NOT Xiangshan's
                             16-RVC layout.
  - br slot 0 (conditional):
      valid, offset, target, always_taken, conf[2:0]
  - br slot 1 (conditional):
      valid, offset, target, always_taken, conf[2:0]
  - jump slot (terminal):
      valid, offset, target (FULL WIDTH, see F9), isCall, isRet,
      isJalr
  - fallthrough: pftAddr + carry  (sized per F12, NOT Xiangshan
                                   12/20-bit)

### F9 -- Target storage: offsets, EXCEPT jump-slot is full-width
Conditional slot targets: stored as OFFSET-from-block-start, with a
fit/overflow/underflow status field (cf Xiangshan TAR_FIT/OVF/UDF).
Offset storage is lossless (target reconstructs exactly) -- it is an
area win, NOT a performance tradeoff. The only cost is a
reconstruct-and-bounds-check step (logic, not accuracy).

Jump slot target: FULL WIDTH. This is load-bearing, NOT optional.
Reason: ITTAGE has no IT0 base table, so an ITTAGE MISS produces NO
ITTAGE target at all. The FTB jump-slot target is the architectural
fallback target for the terminal control instruction:
  - direct unconditional jump (JAL fixed target): FTB jump target IS
    the answer.
  - indirect (JALR): ITTAGE overrides ON HIT; on ITTAGE miss, fall
    back to FTB jump target (last-seen target).
  - return: RAS overrides; FTB jump target is fallback if RAS
    empty/invalid (connects to the RAS commit-stack fallback already
    built).
Consequence to document as an explicit interface contract: the
override chain has an implied "...else FTB jump target" FLOOR. FTB
must keep the jump-slot target FRESH even for branches ITTAGE/RAS
normally own -- it cannot stop tracking a JALR target just because
ITTAGE usually covers it. This ITTAGE-miss fallback path is currently
undocumented anywhere and is a real integration-time bug risk if not
written down.

### F10 -- always_taken: kept
Per conditional slot. "This branch is always predicted taken, skip
the direction predictor." Subsequent predictors can adopt directly.
Priority over confidence counter -- see F11/C-block.

### F12 -- Offset/fallthrough widths sized for expanded instructions
pacino expands RVC to 32b equivalents upstream. The FTB addresses
instructions at the EXPANDED granularity, not RVC 2-byte granularity.
Therefore DO NOT inherit Xiangshan's BR_OFFSET_LEN=12 / JMP_OFFSET_LEN
=20 / pftAddr sizing -- those exist to address 16 RVC instructions at
2-byte granularity inside a block. Recompute all offset widths,
pftAddr width, and carry against pacino's expanded-instruction block
layout. This is an explicit divergence; flag it loudly in the doc so
no one silently copies the Xiangshan widths.
Open: confirm whether a "last_may_be_rvi_call" equivalent is needed.
With RVC pre-expanded, block boundaries may not split a call, which
would make it moot -- a simplification worth claiming if it holds.
Verify against pacino block-boundary behavior.

---

## 3. Confidence Override Decisions (own planning doc)

This is a MULTI-PREDICTOR interaction, not a within-FTB detail. It
touches the override chain, the FTQ-carried prediction fields, and
the execute-stage training path. It gets its own document:
ftb_confidence_override_rules.md.

### C1 -- 3-bit saturating confidence counter, per conditional slot
conf[2:0], one per conditional branch slot (2 per entry). Range 0-7.
Counts FTB's per-slot direction accuracy.

### C2 -- Training: unconditional on FTB correctness, at execute
At execute, for a resolved conditional branch:
  ftb_would_have_been_correct = (ftb_pred_dir == resolved_dir)
  -> increment conf if correct, decrement if incorrect (saturating).
Training is INDEPENDENT of whether FTB's output was actually used or
caused a redirect. It is a pure observer of "is FTB right about this
branch's direction."
Rationale: if training were gated on FTB's prediction being USED, the
counter would have a blind spot exactly where TAGE keeps overriding
FTB -- conf would never move, suppression would be unreachable for the
branches that need it. Unconditional training has no feedback-loop
pathology (pure observers don't). Execute already has resolved_dir;
ftb_pred_dir is carried in the FTQ entry. No new information path.

### C3 -- Acting: suppress DIRECTION overrides only, at s2
When conf >= FTB_CONF_SUPPRESS_THRESH, suppress a TAGE/SC DIRECTION
override for that slot: FTB's direction stands, no redirect bubble.
Scope is DIRECTION ONLY. Target overrides (ITTAGE/RAS) are NEVER
suppressed.
This inverts the clean "SC > TAGE > FTB" priority into "...unless FTB
is confident" FOR DIRECTION. Every downstream direction-override
integration must account for it. Legitimate performance play: avoid
the redirect bubble when the fast predictor is reliably right; the
bigger predictors are not infallible and the bubble has real cost.

### C4 -- Training/acting asymmetry (document both halves)
The counter TRAINS unconditionally (every execute) but ACTS only
selectively (s2, conf>=thresh, direction-only). These are two
contracts on the same 3-bit field. A reader seeing only the
suppression rule will wonder how conf ever got high enough; a reader
seeing only the training rule won't know it gates anything. State
both.

### C5 -- always_taken has PRIORITY over the confidence counter
On a conditional slot, if always_taken is set, that is the direction
and the confidence-suppression logic is not consulted for that slot.
The counter still TRAINS (harmless observation) but does not ACT when
always_taken owns the decision.
Consequence: two independent reasons FTB direction can stand against
a TAGE override -- always_taken (unconditional, older mechanism) and
conf>=thresh (earned). always_taken checks first.

### C6 -- Chicken bit gates SUPPRESSION ONLY; training always runs
A global enable disables the confidence SUPPRESSION (the acting half)
while leaving TRAINING running. This lets the feature be enabled
mid-run or measured with suppression off without a cold counter --
eval-friendly, costs nothing.
CRITICAL: the chicken bit gates the CONFIDENCE path only. It does NOT
gate always_taken (C5) -- that is a separate, older mechanism. Under
chicken-bit-off, always_taken still suppresses. Do not let the doc
accidentally let the chicken bit disable always_taken.

### C7 -- Suppress threshold: parameter, default 6
FTB_CONF_SUPPRESS_THRESH = 6 (top two states of 0-7 = strong-
confidence band). A parameter, not a baked constant, so it can be
swept.

### C8 -- Reset value on (re)allocation: parameter, default 3'b011
FTB_CONF_INIT = 3'b011, compile-time parameter. On entry
(re)allocation the conf counters reset to FTB_CONF_INIT (a low-range
value, below threshold). A freshly allocated entry starts slightly
pessimistic and must climb to threshold by confirmed correctness
before it can suppress.
Rationale: a new entry must NOT override TAGE until proven; starting
at 3 (just below midpoint) rather than 0 means it doesn't crawl from
the floor for a predictable branch. Reset-on-allocate prevents a
reallocated entry from carrying a PREVIOUS branch's confidence
(stale-counter bug).
INVARIANT to assert: FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH. If
init >= thresh, fresh entries are immediately suppressive, defeating
the training gate. Carry a cheap assertion.

### C9 -- Slot-1 training gated on executed path
"Train always" means train every time the branch is RESOLVED AT
EXECUTE, NOT every cycle the entry is read. On a slot-0-taken cycle,
slot 1's block at pred_pc+32 is never executed (independent-blocks,
F2), so there is no resolved direction for slot 1 -- nothing to train.
This falls out of "train on resolution" rather than "train on read";
no special-casing needed, but state it so the counter does not train
on squashed slot-1 phantoms.

---

## 4. Open Items Carried Into Doc-Crafting

- F12-open: confirm last_may_be_rvi_call equivalent is needed or
  moot under pacino RVC pre-expansion. Verify against block-boundary
  behavior.
- Index/tag exact widths: derive from final FTB_SETS and VA_WIDTH
  during doc-crafting; depends on F12 expanded-instruction layout.
- Update/allocation path (replacement policy, when entries allocate,
  pseudo-LRU vs other): NOT discussed in session-051. Needs a
  decision pass. Xiangshan uses pseudo-LRU updated from both
  prediction-hit way and update-write way. Candidate starting point,
  not yet chosen.
- Parameters to add to bp_defines_pkg.sv at RTL task time:
  FTB_WAYS, FTB_SETS, FTB_CONF_SUPPRESS_THRESH, FTB_CONF_INIT,
  plus offset/tag/target widths from F12. (Mirror the RAS pattern:
  names listed in the decision doc, added to the package at RTL task.)
- The confidence-override policy may interact with TAGE's existing
  update/meta path at integration. Not analyzed yet. Flag for
  bp_cluster integration.

---

## 5. Provenance

All decisions above are Jeff's, made in pa session-051 with Claude.ai
as PA. Reference data (Zen/Apple/Xiangshan sizing, associativity
literature) was retrieved and summarized this session; the design
choices are Jeff's dictation per the dictate-vs-propose split.

This record is the session-051 architecture-discussion output. The
formal planning docs (ftb_decisions.md, ftb_interfaces.md,
ftb_confidence_override_rules.md) are to be expanded from this in a
fresh session, then task files (BP-0xx) generated from those.

