# Session Handoff 079
Written by Claude.ai during session-078.
Date: 2026-10-12

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

FIVE TASKS RAN THIS SESSION, BP-128 TO BP-132, AND ALL FIVE ARE
RECORDED. ONE TASK IS WRITTEN AND WAITING: BP-133 (TD#18, 78, 79, 89,
90). The TD scrub of session_handoff-078 Job 1 is finished. The next
session starts by issuing BP-133 and recording its results; the CSR
definition (TD#178) follows once those five TDs are closed.

---

## Read This First

### 1. BP-133 is written, not issued.

prompts/BP-133.md, delivered session-078. The last front-end TDs
before the CSR work. For TD#18 (T0's update side), TD#78 and TD#79
(the RAS recursion pop and the commit-stack recursion depth), the IA
finds out whether each still applies, proposes, and implements a
provisional fix if one is needed. TD#89 and TD#90 (branch PC[15:6]
and the backwards-branch sign for the SC update) get the same freedom
and the change is made; every tb_fe_top program's retired
instructions, cycles and mispredicts are recorded before and after, at
1 and 2 slots. Planning documents are read-only to the IA: proposed
text comes back in Results Capture and the PA applies it with
checksums.

The paths of tage_bim.sv, ras.sv, tb_ras.sv and sc.sv in its Context
Loaded are the PA's assumption; the task tells the IA to use the real
location and say so.

### 2. Scope is Jeff's, every time.

Nothing is opened, written into a document or put in a task without
Jeff ruling that item by name. Bring facts; recommend nothing beyond
the item asked about.

### 3. Do not consume context for nothing.

Ask only for the files the work in hand needs, and say why each is
needed. File names and paths are in PROJECT_STATUS.md (Module Status
and the session entries); look them up there, do not guess them. The
PA does not need the RTL to write a task whose finding is the IA's
job. This session the PA asked for RTL it did not need and guessed
names it could have looked up (Postmortem 7).

### 4. Ask for files first, read what is used.

List every file needed before writing anything. Do not present a
finding that depends on a file not yet read. Read every line of what
is used, and say so when a read is partial.

### 5. Plain English.

Never use a label ("Option A", "D2") without saying in words what it
is. Jeff, session-078: "Throwing out an arbitrary label does not
help."

### 6. Issue files when they change.

Every changed file is sent to Jeff when the change is made, without
being asked: the planning document, PROJECT_STATUS.md and
check_planning.sh together.

### 7. The git wording, verbatim in every task file.

"the IA runs no git command. It may run tools/regress.sh, which makes
git calls of its own; that grant is to run the script, not to run any
command the script contains. Reading regress.sh to see what it calls
grants nothing either."

---

## Session Summary

### Rulings by Jeff

```
  TD#5, 16, 17      closed (decode_pkg reserved values; no T0 padding;
                    tage_table naming)
  tage_table_intf   PA-direct correction: use_wr_u0 / epc_wr_u0 open
                    on a prm or alt selector match
  BP-128 D1         history and rollback ports sized: FIX (BP-129,
                    BP-130)
  BP-128 D2         ON HOLD, then DEFERRED to TD#179 with the block
                    split, entry shape, region sharing (TD#168), uBTB
                    duplicate fill, BP-119 placement and the training
                    point
  BP-128 D3, D4, D5 accepted as built
  history correction up to two bits at either slot count; the cap
                    stays at two
  BP-129, BP-130    provisional decisions accepted
  BP-131            the tb_fe_top programs are directed tests, not
                    representative enough to drive the slot decisions;
                    the next phases measure compiled benchmarks
  TD#82, TD#83      closed; bp_history_decisions.md 6.6 cites no
                    external implementation ("that organization did
                    not originate in xiangshan, it is well known")
  BP-132            provisional decisions accepted, including the
                    cluster boundary keeping tage_upd_rdy /
                    ittage_upd_rdy
  new table         Performance / Verification Debt, after Technical
                    Debt; TD numbers from one sequence across both
  TD#40             closed; the note was removed session-057
  TD#43             closed; the ITTAGE confidence counter stays 3 bits
  TD#97             closed; no shared upstream PQ, not needed
                    (bp_arb_spec.md 8.2, 11.D)
  TD#18, 78, 79,    one IA task, BP-133, with freedom to find out,
  89, 90            propose and implement provisionally; 89 and 90
                    measured before and after
  TD#178            after BP-133's TDs are closed
```

### Tasks run

```
  BP-128  NUM_PRED_SLOTS 1 or 2 from BP_NUM_PRED_SLOTS. 261 PASS (106
          _1slot targets). ittage_table slot count and a tb_loop_pred
          false PASS fixed. TD#1 closed
  BP-129  history and FTQ rollback ports sized by NUM_PRED_SLOTS;
          PRED_CNT_BITS; fold_all_step one loop. 261 PASS. TD#82 done
  BP-130  two-bit correction at either slot count; RB_CORR_BITS,
          RB_CNT_BITS. 261 PASS. At 1, every program back to its
          figures before BP-129
  BP-131  measurement only, nothing changed. Mispredict cost about 11
          cycles; region sharing and one-slot placement measured;
          deferred to TD#179
  BP-132  clean-up: TD#49, 52, 77, 129, 130, 131, 147, 176, 177.
          265 PASS (tage_arb.sv, ittage_arb.sv lint)
```

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md
  arch:   bp_arb_spec, bp_history_decisions, ftb_decisions
  intf:   bp_history, ftq_bpu, ittage, tage, tage_table, ubtb
```

---

## Next session (079)

### Job 1: BP-133.

Jeff issues it. The PA records the results: each TD's finding and
what was done, the before and after tb_fe_top tables, every
provisional choice for Jeff's ruling, and any proposed planning text
(applied only on Jeff's ruling, with checksums). Files the PA will
need then: prompts/BP-133.md with its Results Capture, and the
planning documents the proposed text names.

### Job 2: TD#178, the CSR definition (Jeff).

A new planning file, csr_decisions.md, owning FE-20's config group
(sc_enable, ftb_fastpath_en, tage/ittage aging bits, decode's
ext_enable) and FE-U6. OPEN, for Jeff when tasked: whether it also
covers FE-20's csr group (V, privilege, satp, vsatp, hgatp, pmpcfg,
pmpaddr). Files the PA will need first: fe_decisions.md,
bp_arb_spec.md, and whatever planning documents name those signals;
list them to Jeff before drafting.

### Open, not tasked

```
  Technical Debt   TD#2, 3, 6 (rename, dispatch, vector execution);
                   TD#173 (cachegen CG-5 comparison and gaps)
  Perf / Verif     TD#80, 85, 86, 93, 98, 118, 120, 128, 133, 149,
  Debt             150, 168, 179 (moved); TD#180, 181 (coverage,
                   for the formal verification exercise)
  new table rows   not yet asked: whether any row moved to the
                   Performance / Verification Debt table should stay
                   in Technical Debt
  comments         bp_history.sv and tb_bp_history.sv comments still
                   mention XiangShan; change only if Jeff asks
```

### Pending rulings carried from session_handoff-078, not raised

```
  BP-123 Asm 2, 3, 7  IF-36, IF-30, the walker's CSR group (MMU-24a)
  dcd 10b             the PA additions dcd_decisions.md 10b lists
  git amendment       the session-075 ruling item 3 amendment
  L1I-U7              prefetch reserve on the link or the node
  CG-U1, CG-U2        cachegen_decisions.md 5
  FE-U4, FE-U5        PHR in the hashes; indirect chain update
  CU-03, CU-04        tage_coverage_plan primary-provider CTR rows
```

### Later, in order

```
  benchmarks          compiled benchmarks and a backend model for
                      performance numbers; TD#179 and the measurement
                      TDs wait on it
  formal flow         with the coverage exercise (TD#180, 181)
```

### For Jeff to apply

- drop rtl/core/frontend/decode/obj_dir_pre from the root .gitignore
  (carried since BP-122), if not already done.

### Numbers

```
  next free BP     BP-134
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#182
```

---

## IA behaviour, recorded

- No departure from a grant was reported to the PA for BP-128 to
  BP-132. The session was compacted; the PA's record of those Results
  Captures is a summary, not a re-read for grant departures.

---

## Postmortem Record -- PA performance (session-078)

1. ARBITRARY LABELS. I used "Option A" without saying what it was.
   Jeff: "why dont you improve how you communicate these things.
   Throwing out an arbitrary label does not help."

2. WRONG WORD. I called the uBTB duplicate fill and the BP-119
   placement "defects"; both follow their written rules. Corrected.

3. WRONG STATUS. I listed TD#7 as open; BP-122 had closed it.

4. TOOL DAMAGE. My PROJECT_STATUS row-append helper corrupted the
   first column of single-line rows. Caught and rerun from a clean
   copy.

5. TRANSPOSED NUMBERS. TD#179 read "312 / 27" for two slots / one
   slot; it is 27 / 312. Fixed.

6. CUT-AND-PASTE NOT QUERIED AT ONCE. A ruling read "leave it 3 bits"
   and "TD#43 gets the same freedom". I asked, which was right, but
   only after a longer answer than needed.

7. CONTEXT WASTED. Asked for BP-133's files, I requested RTL I did not
   need, guessed planning file names that PROJECT_STATUS.md lists,
   and lumped ras.sv and tb_ras.sv in with "planning files". Jeff:
   "isnt it your job to manage and minimize the amount of context you
   consume ?" BP-133 was then written from the TD rows alone.

8. WORK NOT DELIVERED. After closing TD#40, 43 and 97 I did not send
   the changed files or write BP-133 until Jeff asked: "are you
   issuing the files or what ?" and "is there a fucking task for the
   IA or not ?"

What worked: pointing out the conflicting D2 answers before building
on them; checksum updates with every document change; the
measurement task (BP-131) before deciding the block split.
<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
