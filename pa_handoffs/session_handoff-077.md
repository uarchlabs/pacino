<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 077
Written by Claude.ai during session-076.
Date: 2026-10-09

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

THE PREDICTION SIDE OF THE FRONT END IS DONE. BP-121 and BP-122 are
recorded in the planning documents and nothing from either is left
open. BP-123, the IFU completion task (FENCE.I, cbo.inval, uncached
fetch), is written and has not been run.

---

## Read This First

### 1. BP-123 is written, not run.

prompts/BP-123.md. It builds TD#119, TD#135 and TD#136 against a
pacino copy of the l1i in rtl/core/frontend/icache. Its Results
Capture must list every port added or changed with its declaration,
and every difference between the l1i copy and the emitted l1i.

### 2. Four rulings this session change the IFU's memory path.

```
  IFU-21 REVERSED   uncached fetch goes through the L1I, marked
                    uncached: a forced miss, no allocation
                    (L1I-24, IF-44). There is no second source.
  IFU-22, IFU-23    stand: commit-gated, one instruction at a time
  MMU-15b           non-idempotent memory is never executable;
                    closes IFU-U4 (no narrow uncached read)
  CG-4, CG-D1       the l1i is changed in the pacino RTL, not in
                    cachegen; CG-5 reconciles later
  L1I-25            the L2 may hold an uncached line while it is
                    the point of coherence (Svpbmt checked)
```

FE-17 lost its uncached boundary group. TD-L1I-2 is closed (cbo.inval
routed, IF-41).

### 3. Open items must not be carried.

Jeff, session-076: end-state tasks close everything; nothing is
carried except by his ruling. Ruled items are labelled as such, not
OPEN (TD#168 relabelled "KEPT by ruling, not open work"; misp_call's
conditional recorded as unlearnable). Each task file lists every
decision in scope before it is written.

---

## Session Summary

### Rulings by Jeff

```
  BP-121 recording    all nine BP-121 decisions in their documents
  loop predictor      banks stay one per slot (TI6); "slot 1 wins"
                      has no case to apply to
  BP-122 scope        all five candidates
  BP-122 in session   restore option A; a trusted LP wins at p2 and
                      p3 (LP > SC > TAGE > FTB); lp and loops
                      lengthened
  TD#165              closed, unreachable by construction
  lp_pred_t fields    leave them (no package change)
  IFU memory path     the four rulings above
```

### Tasks run

```
  BP-122  loop predictor in use (TD#169, TD#7), properties for every
          BP-121 fix (TD#170), three cleanups, the five BP-121 port
          details reported. 123 targets PASS. lp 7 -> 1 mispredicts
          after warm-up, loops 2 -> 1; nothing else changed
```

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md
  arch:   bp_arb_spec, bp_cluster, bp_history, cachegen, fe, ftb,
          ftb_confidence_override_rules, ftq, ftq_entry_formats,
          icache, ifu, mmu, ras
  intf:   bp_history, ftb, ftq_backend, ftq_bpu, itlb_ifu, l1i_ifu,
          loop_pred, ras, sc, tage, ittage, ubtb
```

---

## Next session (077)

### Job 1: process BP-123 when it has run.

Record its results in the documents its proposals name, close
TD#119, TD#135, TD#136, and close or rule every item it leaves.
Nothing is carried except by Jeff's ruling.

### Job 2: the verification and cleanup task.

Scope listed to Jeff in session-076 (the "what does #2 entail"
answer): TD#67, 68, 69, 70, 84, 100, 37, 75, 1, 102, 103, 121, 101,
148, 104 and the comment-only RTL list, 49, 52, 16, 17, 18, 147,
129, 130, 123, 43. Six decisions are needed before it is written;
PA recommendations given, NOT YET ANSWERED:
```
  TD#1    drop the NUM_PRED_SLOTS=1 build            (Rec.)
  TD#123  record the cluster SC arbiter as the design,
          close                                      (Rec.)
  TD#43   close, ITTAGE counter stays 3 bits         (Rec.)
  TD#121  RAS commit stack wrap flag, no rebalance   (Rec.)
  TD#52   close, arbitration stays in the tops       (Rec.)
  TD#129, 130  include with a tools/ grant           (Rec.)
```
TD#104's "112 bits" is itself stale; the RAM entry is 113 since
BP-121.

### Later, in order

```
  L2 TLB and walker   MMU task; not needed by the front end
                      (formal and performance work stand in for
                      the refill port)
  backend model       trace-driven, for performance numbers; the
                      measurement TDs (149, 150, 133, 120, 128, 80,
                      93, 86, 98) wait on it. INFRA
  formal flow         if wanted; no tool in the tree. TOOLS
```

### For Jeff to apply

- drop rtl/core/frontend/decode/obj_dir_pre from the root .gitignore
  (BP-122).
- Open Items row 1 says "TOOLS-003 open"; the PA thinks it is stale.

### Numbers

```
  next free BP     BP-124
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#171
```

---

## IA behaviour, recorded

- BP-122 put "TD#168 unchanged", "TD#165 unreachable" and "no package
  changes" under "Still open". The first two were open only because
  PROJECT_STATUS labelled them OPEN (PA); the third was a placement
  error.
- BP-122 left two wait loops running after the session: pgrep -f
  matched the loops' own command lines. Saved to its memory; BP-123
  states the rule.
- BP-122 showed every property firing except H2 (bp_history
  checkpoint rewrite), and said so.

---

## Postmortem Record -- PA performance (session-076)

1. TASK GAP. BP-121 asked for package changes with reasons but not
   for added ports with declarations, so five interface details came
   back as names only and the PA first asked Jeff for a grep. Jeff:
   "why isnt this part of the IA's task?" Fixed: BP-122 and BP-123
   require every port added or changed, with its declaration.

2. OPEN ITEMS LEFT OPEN. The PA labelled a ruled item OPEN (TD#168),
   left TD#165 out of BP-122 and listed it as "can wait". Jeff: "were
   you not instructed to close this out?" Yes. Fixed by relabelling
   and closing TD#165 by ruling.

3. A CONFLICT OFFERED AS AN OPTION. The PA offered sharing the loop
   predictor table between slots, which would create the write
   conflict the per-slot banks avoid. Jeff: "why in the hell would
   you create a conflict on purpose?"

4. RECOMMENDING BEFORE READING. The PA recommended option 1 for
   uncached fetch before reading ifu_decisions.md, which had already
   ruled the opposite (IFU-21) and which raised the device-side-effect
   problem. Caught when the documents arrived, before anything was
   written; the ruling became five parts.

5. PARTIAL WRITES. One edit script stopped mid-file on a wrong
   anchor and left the earlier edits of that file applied. Recovered
   by re-running the remainder; the final checksums are from the
   finished files.

What worked: checksum verification of every input before editing
and every output after; the one-anchor replace helper; an
independent agent checking every added line against BP-121.md,
which found nine errors before delivery.
