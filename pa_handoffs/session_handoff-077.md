<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 077
Written by Claude.ai during session-076.
Date: 2026-10-09

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

THE PREDICTION SIDE OF THE FRONT END IS DONE. BP-121 and BP-122 are
recorded in the planning documents and nothing from either is left
open. BP-123 IS TO BE WRITTEN THIS SESSION. A draft written in
session-076 covered the IFU only and was DISCARDED by Jeff as
incomplete.

---

## Read This First

### 1. BP-123 is the first job, and it has three parts.

Jeff, session-076: one end-state task covering the IFU completion,
the MMU walker, and the RVA23 Z* checks (Job 1 below). The
session-076 draft held the first part only and is discarded; do not
build on it. Its Results Capture list (every port added or changed
with its declaration; every difference between a pacino copy of a
cache and its emitted original) carries into the new task.

### 2. Rulings this session that change the IFU's memory path.

```
  IFU-21 REVERSED   uncached fetch goes through the L1I, marked
                    uncached: a forced miss, no allocation
                    (L1I-24, IF-44). There is no second source.
  IFU-22, IFU-23    stand: commit-gated, one instruction at a time
  MMU-15b           non-idempotent memory is never executable;
                    closes IFU-U4 (no narrow uncached read)
  CG-4, CG-D1       the l1i is changed in the pacino RTL, not in
                    cachegen; CG-5 reconciles later
  L1I-25            the future L2 may hold an uncached line while
                    it is the point of coherence (Svpbmt checked).
                    No L2 exists today and none is in BP-123
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
  IFU memory path     the rulings above
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

### Job 1: write BP-123 (Jeff, session-076).

ONE END-STATE TASK, BP-121's grants and method, in three parts.
Settle the decisions listed under part B first, so the task carries
none.

A. IFU COMPLETION: TD#119, TD#135, TD#136. Rulings recorded
   session-076 (Read This First 2):
   - copy the emitted l1i (tools/cachegen/output/l1i/, with l1i_pkg
     and its testbench) into rtl/core/frontend/icache under CG-D1;
     show the copy passes the emitted testbench before changing it;
     switch fe_top and l1i_param_chk to it;
   - add the maintenance ports of l1i_ifu_interfaces.md 10 (IF-28
     to IF-32, IF-42: drain then clear) and the uncached bit
     (IF-44, L1I-24: forced miss, no allocation);
   - the IFU maintenance path of l1i_ifu_interfaces.md 11 (IF-33 to
     IF-37; the line buffer cleared after inv_done) and the uncached
     path (IFU-21 as reversed, IFU-22, IFU-23, IFU-26, never a
     prefetch);
   - fe_top carries the maintenance group (FE-17, backend group);
   - MMU-15b: the checker rejects an executable non-idempotent
     region at elaboration, with a negative lint target (needs a
     write grant for rtl/mmu/pmp);
   - programs: FENCE.I after a store changes cached code; cbo.inval
     of one code line; both with fetches in flight and a redirect
     near them; uncached fetch from an NC page and an IO page under
     sv39, branching into, within and out of the page; every cycle
     of every program checks that no uncached request is presented
     before older instructions commit and no uncached line is
     allocated.

B. THE MMU WALKER. The L2 TLB and walker are "Not started"
   (PROJECT_STATUS module rows); tb_fe_top's sv39 walks are answered
   by the testbench on the ITLB refill port. RVA23S64 needs a
   hardware walk (Ssccptr; RISC-V has no software TLB refill): Sv39,
   nested Sv39x4 for Sha (MMU-19 to MMU-23, MMU-26), Svade, the
   reserved-NAPOT and PBMT PTE checks (MMU-U6, MMU-U7), and the PMP
   check on every walker access (MMU-10). Svinval needs nothing new
   (MMU-U8). The sv39 programs then walk in RTL, with programs for
   both stages, every fault cause (1, 12, 20, MMU-16) and a 64 KiB
   NAPOT mapping at each stage (MMU-U7's test requirement).

   DECISIONS BEFORE THE TASK IS WRITTEN, put to Jeff session-076,
   NOT YET ANSWERED (PA recommendations):
```
  MMU-1   reverse: no L2 TLB now; ITLB misses go to the walker
          directly. An L2 TLB is a later performance step, with
          the DTLB. Closes MMU-U1 and MMU-U2.         (Rec.)
  MMU-6   narrow to Svade only; Svadu is not mandatory in RVA23.
          Removes the atomic A/D update, MMU-9's atomic edge and
          the cachegen half of MMU-U3.                 (Rec.)
  MMU-U9  a PTE PPN above PPN_WIDTH (24): check the ratified
          privileged text for the required fault (page fault at
          the stage, or access fault) BEFORE ruling. Required
          either way.
  memory  how the walker reaches memory. There is no L2 today
          and none in BP-123 (Jeff, session-076); MMU-2's port into
          the L2 is the future plan and stays as written. Rec.:
          for BP-123 the walker has its own memory read port,
          answered by the testbench memory model as the L1I's
          memory port is.
```
   The interface is itlb_l2tlb_interfaces.md (IL-*); read it
   before writing part B. Under MMU-1 reversed, its client is the
   walker rather than an L2 TLB, which may change IL-* text.

C. RVA23 Z* CHECKS. The IA reports, with evidence from the RTL and
   a test for each, how the RVC expander and the decoder handle the
   RVA23U64 mandatory extensions that touch them: Zcb and Zcmop
   (whether BP-117's LLVM check enabled them), Zimop (non-trapping
   may-be-operations), and Zicbop's prefetch.i (a hint; accepted).
   And whether an aligned 32-bit instruction fetch is atomic
   (Ziccif); confirm the clause against rva23-profile.adoc first,
   which the PA did not. Any gap found is fixed in the task.

END STATE: every new and earlier program retires exactly and is a
regression target; every rule named is built with a check or
property that fails when its logic is reverted; the 19 earlier
programs' cycles and mispredicts are unchanged or each change is
explained; part C's report is complete with no gap left; no known
correctness defect is open; tools/regress.sh passes.

### Job 2: process BP-123 when it has run.

Record its results in the documents its proposals name, close
TD#119, TD#135, TD#136 and the walker row, and close or rule every
item it leaves. Nothing is carried except by Jeff's ruling.

### Job 3: the verification and cleanup task.

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
  must state the rule (wait on a job's exit or a done-file).
- BP-122 showed every property firing except H2 (bp_history
  checkpoint rewrite), and said so.

---

## Postmortem Record -- PA performance (session-076)

1. TASK GAP. BP-121 asked for package changes with reasons but not
   for added ports with declarations, so five interface details came
   back as names only and the PA first asked Jeff for a grep. Jeff:
   "why isnt this part of the IA's task?" Fixed: BP-122 requires,
   and BP-123 must require, every port added or changed, with its
   declaration.

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

6. AN INCOMPLETE TASK. BP-123 was first written for the IFU alone,
   while the RVA23 walk was missing and the Z* checks were known to
   be unverified. Jeff discarded it; it is rewritten in session-077
   with all three parts.

7. A FUTURE STRUCTURE IN THE NEXT TASK. The PA proposed copying
   "the emitted l2" into BP-123 for the walker, when no L2 exists
   today and none is planned for the front end now. Jeff: "there is
   NO ... L2". The PA then overcorrected and withdrew L1I-25 from
   the documents, where the future L2 belongs; Jeff: "removing it is
   stupid". Restored. Lesson: the L2 stays in the documents as the
   future plan and stays out of BP-123 and session-077's plan.

What worked: checksum verification of every input before editing
and every output after; the one-anchor replace helper; an
independent agent checking every added line against BP-121.md,
which found nine errors before delivery.
