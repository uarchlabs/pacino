<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# FTB Decision Record
```
 FILE:    ftb_decision_record.md
 SOURCE:  session-051 (prediction) + session-052 (update)
 STATUS:  COMPLETE -- all decisions ruled
 UPDATED: 2026-06-24
 CONTACT: Jeff Nye
```

Complete architectural decision record for the FTB (Fetch Target
Buffer). Prediction side decided session-051 (F1-F12), update/evict
side decided session-052 (F13-F20, F19a). This is the full decision
set. The formal planning documents are expanded from this:

  - planning/arch/ftb_decisions.md            (canonical authority)
  - planning/interfaces/ftb_interfaces.md     (interface contract)
  - planning/arch/ftb_confidence_override_rules.md  (override policy)

Mirror the RAS pair (ras_decisions.md + ras_interfaces.md) for the
first two. The confidence doc is new (no RAS analog).

Reference designs consulted: Xiangshan Kunminghu FTB (primary model),
AMD Zen 2-5 BTB hierarchy (sizing), Apple M2 (sizing anchor),
Bray/Flynn Stanford BTB study (associativity). Divergences from
Xiangshan are called out explicitly -- this is not a straight port.

All decisions are Jeff's, made per the dictate-vs-propose split.
Reference data was retrieved and summarized by the PA; the choices
are Jeff's.

---

## 0. Context and Prior Constraints (fixed before this record)

FTB must obey these, settled earlier:

- FTB lives at s2, alongside TAGE, ITTAGE, RAS.
- Override chain: SC > TAGE > FTB > uBTB. FTB overrides uBTB;
  TAGE/SC override FTB on direction; ITTAGE/RAS override FTB target.
- FTB classifies branch type for the whole cluster. It tells RAS
  "this is a return", ITTAGE "this is an indirect", and supplies the
  fallthrough address. The three-way JALR split (FTB / RAS / ITTAGE)
  is resolved by FTB structural prediction before s2.
- FTB owns the fallthrough address RAS pushes (ras_fall_through_p2).
- NUM_PRED_SLOTS = 2. Fixed bundle split (G8): slot 0 = pred_pc+0:31,
  slot 1 = pred_pc+32:63. Slot 1 PC always pred_pc+32 (G17, static).
- TI6: banks are per-slot RAMs. RAM0 serves slot 0, RAM1 serves
  slot 1. Selection is structural.
- pacino expands RVC instructions to 32b equivalents upstream. This
  changes the instruction granularity the FTB addresses (see F12).
- ITTAGE has no IT0 base table (bp_cluster.md). Load-bearing for the
  FTB jump-slot target (see F9).
- Update happens post-execute, not at retire.

===================================================================
# PREDICTION SIDE (session-051)
===================================================================

## 1. Structural Decisions

### F1 -- Per-slot RAMs, no second read port
FTB follows TI6. Two FTB RAMs, RAM0 -> slot 0, RAM1 -> slot 1, one
read each. No second read port. Two independent block lookups per
cycle, one per slot-RAM. (Update adds a write port -- see F19. "No
dual-port" here means no second READ port.)
Rationale: matches TAGE/ITTAGE convention; avoids a 2-read array;
cost is area (two RAMs) not port complexity.

### F2 -- Independent-blocks model
Each slot is its own FTB lookup producing its own prediction. Slot 1
always reads at pred_pc+32 (static per G17), regardless of slot 0.
Cross-slot taken-priority (if slot 0 has an earlier taken branch,
slot 1's block is not executed) is resolved downstream, not in FTB.
Slot 1 work is computed then discarded on slot-0-taken cycles.
Rationale: consistent with the fixed-boundary G8/G17 decision, which
already rejected a data-dependent slot-1 start. Accepts the wasted
slot-1 work as the cost of no serial dependency.

### F3 -- Associativity: 4-way, parameterized
FTB_WAYS = 4 baseline. Parameterized so 8-way is a synthesis
experiment, not a redesign.
Rationale: Xiangshan uses 4-way at the same 2048-entry capacity -- a
working silicon decision at our size. No public data quantifies the
4->8 way accuracy gain at 2048 entries; at that capacity conflict
misses are already low and associativity has diminishing returns.
Commercial designs engineer around high associativity, which signals
it is expensive, not free. 8-way was an unmeasured belief. Circle
back with own SPEC numbers if time allows.

### F4 -- Capacity: 2048 entries/slot baseline, parameterized
FTB_SETS parameterized. Baseline 2048 entries/slot = 512 sets x
4-way, per slot (4096 entries total across both slots). Relief lever:
1024 entries/slot = 256 sets x 4-way, pre-authorized as the
area/timing fallback.
"2048" is per slot, not total. State this explicitly -- per-slot RAMs
make "2048 entries" ambiguous and a silent mis-read causes a
doc-vs-RTL gap.
Rationale: commercial fast single-level BTBs cluster at 512-2048
total (Zen 2/3/4 = 512/1024/1536; Apple M2 ~2048; Xiangshan = 2048).
2048/slot is generous, slightly aggressive; 1024/slot lands in the
proven range. The Zen 5 16K "L1 BTB" is not a counter-example -- it
is the fast tier of a decoupled multi-level design (16K L1 + 8K L2
victim), not one flat array. Bigger designs go multi-level, not
fatter-flat.

### F5 -- Growth path is multi-level, not fatter-flat
If 2048/slot proves short under SPEC, the growth path is a second FTB
level (L2 FTB, victim style), consistent with the decoupled frontend
-- not a larger flat L1. Matches how Zen scales BTB reach.

### F6 -- Timing: FTB is off the zero-bubble path
uBTB is the zero-bubble s1 predictor giving the fast next-PC. FTB at
s2 is therefore not on the critical first-cycle path, which loosens
its timing budget (larger, slower read is acceptable). FTB overrides
uBTB at s2 on the larger-slower-more-accurate presumption. That
override is an s2 redirect with a bubble -- the designed cost that
buys FTB its timing room. Document the bubble as the consequence of
the timing latitude.

## 2. Entry Format Decisions

### F7 -- 2+1 structure: two conditional branches + one jump
Each entry holds 2 conditional branch fields + 1 jump field
(terminal: unconditional jump / call / return). No Xiangshan-style
field sharing. Two conditional branches with no jump fill both
conditional fields directly.
Rationale: Xiangshan shares because it has one dedicated conditional
field and reuses the tail for a second conditional. With two real
conditional fields, sharing is unnecessary -- simpler format, simpler
update, no sharing decode. Cost: always pay for two conditional
fields + a jump field even in the common one-branch block. Named,
chosen tradeoff.
Project stance: trade area for performance. Do not optimize the entry
toward minimum area at the expense of capability.

### F8 -- Entry field list
Per entry:
  - valid          -- entry valid
  - tag            -- 4-way match tag. Width = upper PC bits above the
                      index. Index width from FTB_SETS (512 sets ->
                      9 index bits). Computed against the expanded-
                      instruction block layout (F12), not Xiangshan's
                      16-RVC layout.
  - conditional branch 0: valid, offset, target, always_taken,
                          conf[2:0]
  - conditional branch 1: valid, offset, target, always_taken,
                          conf[2:0]
  - jump field:           valid, offset, target (full width, F9),
                          isCall, isRet, isJalr
  - fallthrough:          pftAddr + carry (sized per F12)
  - last_may_be_rvi_call: 1 bit (F12)

### F9 -- Targets: offsets, except the jump target is full width
Conditional targets: offset-from-block-start, with a
fit/overflow/underflow status (cf Xiangshan TAR_FIT/OVF/UDF). Offset
storage is lossless (target reconstructs exactly) -- an area win, not
a performance tradeoff. Cost is a reconstruct-and-bounds-check step
(logic, not accuracy).

Jump target: full width. Load-bearing, not optional. ITTAGE has no
base table, so an ITTAGE miss produces no ITTAGE target. The FTB jump
target is the architectural fallback for the terminal instruction:
  - direct jump (JAL fixed target): FTB jump target is the answer.
  - indirect (JALR): ITTAGE overrides on hit; on ITTAGE miss, fall
    back to the FTB jump target.
  - return: RAS overrides; FTB jump target is the fallback when RAS
    is empty (connects to the RAS commit-stack fallback).
Consequence (interface contract): the override chain has an implied
"...else FTB jump target" floor. FTB must keep the jump target
current even for branches ITTAGE/RAS normally own -- it cannot stop
tracking a JALR target just because ITTAGE usually covers it. See
F18.

### F10 -- always_taken: kept
One bit per conditional branch. "This branch has been taken every
time, skip the direction predictor." Init and clear rules in F17/F18.
Priority over the confidence counter (C5).

### F12 -- Offset/fallthrough widths sized for expanded instructions;
###        keep last_may_be_rvi_call
pacino expands RVC to 32b before FTB. FTB addresses instructions at
the expanded granularity, not 2-byte RVC granularity. Do not inherit
Xiangshan's BR_OFFSET_LEN=12 / JMP_OFFSET_LEN=20 / pftAddr sizing --
those address 16 RVC instructions at 2-byte granularity. Recompute
all offset widths, pftAddr, and carry against the expanded-
instruction block layout. Flag this divergence so no one copies the
Xiangshan widths.

last_may_be_rvi_call: keep the bit (1 bit). It flags the case where
the last instruction in a block is a call whose second half spills
into the next block; the RAS return address depends on where the call
ends. An instruction straddling a block boundary cannot be guaranteed
not to happen, so the correction is required. The straddle correction
is part of the fallthrough/pftAddr arithmetic computed at doc-
crafting (see open items) -- not a separate stored width. The bit
itself is the only added storage.

## 3. Confidence Override (own planning doc)

A multi-predictor interaction, not a within-FTB detail. Touches the
override chain, the FTQ-carried prediction fields, and the execute-
stage training path. Lives in ftb_confidence_override_rules.md.

### C1 -- 3-bit saturating counter, per conditional branch
conf[2:0], one per conditional branch field (2 per entry). Range 0-7.
Measures FTB's per-branch direction accuracy.

### C2 -- Training: unconditional on FTB correctness, at execute
At execute, for a resolved conditional branch:
  increment conf if (ftb_pred_dir == resolved_dir), else decrement
  (saturating).
Training is independent of whether FTB's output was used or caused a
redirect. A pure observer of "is FTB right about this branch."
Rationale: if training were gated on FTB's prediction being used, the
counter would have a blind spot exactly where TAGE keeps overriding
FTB -- conf would never move and suppression would be unreachable for
the branches that need it. Unconditional training has no feedback
loop. Execute already has resolved_dir; ftb_pred_dir is carried in
the FTQ entry. No new information path.

### C3 -- Acting: suppress direction overrides only, at s2
When conf >= FTB_CONF_SUPPRESS_THRESH, suppress a TAGE/SC direction
override for that branch: FTB's direction stands, no redirect bubble.
Direction only. Target overrides (ITTAGE/RAS) are never suppressed.
This makes the priority "SC > TAGE > FTB ... unless FTB is confident"
for direction. Every downstream direction-override integration must
account for it. The performance play: avoid the redirect bubble when
the fast predictor is reliably right.

### C4 -- Training and acting are asymmetric; document both
The counter trains unconditionally (every execute) but acts only
selectively (s2, conf>=thresh, direction only). Two contracts on one
field. State both -- a reader seeing only suppression wonders how conf
got high; a reader seeing only training won't know it gates anything.

### C5 -- always_taken has priority over the confidence counter
If always_taken is set for a conditional branch, that is the
direction and the confidence-suppression logic is not consulted for
that branch. The counter still trains (harmless) but does not act.
Two independent reasons FTB direction can stand against a TAGE
override: always_taken (older mechanism) and conf>=thresh (earned).
always_taken checks first.

### C6 -- Chicken bit gates suppression only; training always runs
A global enable disables confidence suppression (the acting half)
while training keeps running. Lets the feature be enabled mid-run or
measured with suppression off without a cold counter.
The chicken bit gates the confidence path only. It does not gate
always_taken (C5), which is a separate, older mechanism -- under
chicken-bit-off, always_taken still suppresses. Do not let the doc
make the chicken bit disable always_taken.

### C7 -- Suppress threshold: parameter, default 6
FTB_CONF_SUPPRESS_THRESH = 6 (top two states of 0-7). A parameter,
swept, not baked.

### C8 -- Reset value on allocate: parameter, default 3'b011
FTB_CONF_INIT = 3'b011, compile-time parameter. On allocation the
conf counters reset to FTB_CONF_INIT (below threshold). A fresh entry
starts slightly pessimistic and must climb to threshold by confirmed
correctness before it can suppress.
Reset-on-allocate prevents a reallocated entry from carrying a
previous branch's confidence.
Invariant (assert): FTB_CONF_INIT < FTB_CONF_SUPPRESS_THRESH. If
init >= thresh, fresh entries suppress immediately, defeating the
training gate.

### C9 -- Training counts only resolved branches
"Train always" means train every time the branch is resolved at
execute, not every cycle the entry is read. On a slot-0-taken cycle,
slot 1's block is never executed (F2), so there is no resolved
direction for slot 1 and nothing to train. Falls out of "train on
resolution" rather than "train on read." State it so the counter does
not train on discarded slot-1 reads.

===================================================================
# UPDATE / EVICT SIDE (session-052)
===================================================================

### F13 -- Hit updates, miss allocates
When a branch resolves at execute:
  - Entry for this block already in the set (tag hit): update in
    place. Write the resolved branch's target, always_taken, conf
    (conf per C2). No new entry.
  - Tag hit, this branch not yet stored, a branch field free: write
    it into the free field. conf for that field = FTB_CONF_INIT.
  - No entry for this block (tag miss): allocate a new entry; the
    evicted way is chosen by F15.
The whole block's branches live in one entry, because the entry sets
the block boundary and fallthrough. One branch per entry would not
work.

### F14 -- Track every branch, not just taken ones
Allocate and track any conditional branch or jump that resolves in a
fetched block, taken or not. A taken-only FTB does not work here: a
not-taken conditional that FTB did not store would give TAGE nothing
to override, put the block boundary in the wrong place, and give RAS
the wrong fallthrough.
Cost: more entries than taken-only, so more pressure on the 2048/slot
capacity. If capacity runs short under SPEC, this is the first thing
to revisit, with the F4/F5 relief levers.

### F15 -- Replacement: tree-PLRU per set
On a tag-miss allocate, the evicted way is chosen by tree-PLRU, 3
bits per set for the 4-way. Update the PLRU bits on two events:
  - prediction hit: mark the hit way used.
  - update or allocate write: mark the written way used.

### F16 -- Block ends at the last branch that fits
A block can contain more branches than the entry holds (2 conditional
+ 1 jump). When a block has a third conditional branch with no field
for it: end the block at the second conditional. The fallthrough
points to just after that second branch. The third branch becomes the
first branch of the next fetch block and gets its own entry on a
separate lookup. Branches are never dropped; the block is split.
Cost: that block becomes two fetch blocks, two lookups instead of
one, on that path. Only happens with three or more conditional
branches in one block, which is rare.

### F17 -- Field values when an entry or branch field is allocated
  - valid: 1 for a filled field, 0 for an unused one.
  - tag: the block tag.
  - conf (each conditional): FTB_CONF_INIT (C8).
  - always_taken (each conditional): the branch's resolved direction
    at allocate -- 1 if allocated taken, 0 if not-taken. Cleared later
    by F18.
  - target (conditional): the resolved taken target, as an offset
    with fit/overflow/underflow status (F9).
  - target (jump, full width per F9): the resolved jump target.
  - isCall / isRet / isJalr: from the resolved jump's type.

### F18 -- Field writes when an existing branch resolves
  - conf: per C2 (up if FTB would have been right, down if wrong).
  - always_taken: the first time the branch resolves not-taken, set
    it to 0. Once 0, it stays 0 for the life of the entry. It is set
    to 1 again only if the entry is evicted and reallocated to a taken
    branch.
    Reason: always_taken=1 means the branch has been taken every time,
    so the direction predictor can be skipped. One not-taken outcome
    makes that false. It is not set back to 1 on the next taken,
    because a branch that alternates would otherwise flip the bit back
    and forth and the claim would be wrong. One not-taken ends it.
  - conditional target: rewrite if the resolved taken target differs
    from the stored offset.
  - jump target (full width): rewrite on every resolve of that jump,
    including when ITTAGE or RAS normally supplies the runtime target.
    ITTAGE has no base table, so an ITTAGE miss falls back to this
    stored target; RAS falls back here when empty. The stored target
    must stay current. Do not gate this write on "ITTAGE missed" --
    write it whenever the jump resolves.

### F19 -- RAM ports: one read, one write per slot-RAM
Each slot-RAM has one read port (prediction) and one write port
(update), with independent read and write addresses used in the same
cycle. This is a register file with separate read/write address
ports, or a 1R1W SRAM. F1's "no dual-port" meant no second read port;
the write port was always required.
Same-cycle read and write to the same entry: the read returns the old
value.
1R1W is assumed for now. True dual-port arrays are available on the
target but cost area and power, so the design avoids needing a second
read port where it reasonably can; 1R1W keeps that benefit.
The arrays are a discrete RTL module, separate from FTB control logic,
so a register file or a 1R1W SRAM can be substituted with no change to
surrounding logic. The substitution must be possible without touching
control.

### F19a -- FTB module boundary
FTB is a structural top module containing:
  - the array module(s) (the per-slot 1R1W RAMs, F19)
  - a separate control module (read, branch-type classification,
    block-boundary and fallthrough computation, allocate/evict, update
    field writes, confidence training and suppression)
The top is structural only. Same pattern as keeping arb logic out of
the TAGE/ITTAGE tops (#52), not the single self-contained module RAS
used. The array/control split is what makes the F19 array swap clean.
Outside FTB: FTQ-level update scheduling (F20); cluster-wide override
resolution at s2.

### F20 -- One update port per slot-RAM; FTQ feeds it
FTB exposes one update port per slot-RAM. When several branches
resolve at once, the FTQ routes each to the correct slot-RAM by the
branch's position (pred_pc+0:31 to slot 0, pred_pc+32:63 to slot 1)
and serializes if there are more branches than ports. FTB does not
schedule updates itself.
This is the FTB/FTQ boundary, not an open decision. The multi-branch
scheduling links to G9 (update channel arbitration), resolved at
bp_cluster integration.

===================================================================
# OPEN ITEMS (deferred with a home, not blanks)
===================================================================

These belong to bp_cluster integration or to doc-crafting, not to the
FTB decision set. Listed so they are not mistaken for undecided FTB
architecture.

- Exact index, tag, offset, pftAddr, and carry bit widths: computed at
  doc-crafting from FTB_SETS and the expanded-instruction layout. The
  last_may_be_rvi_call straddle correction is part of this fallthrough
  arithmetic (F12).
- G9 update channel arbitration (linked from F20): cluster-level.
- Confidence-override interaction with the TAGE update/meta path:
  flagged, not yet analyzed. bp_cluster integration.
- Parameters to add to bp_defines_pkg.sv at RTL task time: FTB_WAYS,
  FTB_SETS, FTB_CONF_SUPPRESS_THRESH, FTB_CONF_INIT, plus the widths
  above. (Mirror the RAS pattern: named here, added to the package at
  RTL task.)

===================================================================
# Document History
===================================================================

  2026-06-24  session-051: prediction side (F1-F12, C1-C9).
              session-052: update/evict side (F13-F20, F19a).
              F12 ruled keep-the-bit; straddle correction folded into
              fallthrough arithmetic, not a separate width.
              Merged into this single record. All decisions ruled.
              Next: expand into ftb_decisions.md, ftb_interfaces.md,
              ftb_confidence_override_rules.md. Once expanded, this
              record is frozen history -- the three docs are
              authority; do not maintain all four.

