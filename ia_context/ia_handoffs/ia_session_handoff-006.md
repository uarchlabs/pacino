<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# IA Session Handoff 006
```
 FILE:    ia_session_handoff-006.md
 SOURCE:  the IA interactive session of 2026-10-18
 STATUS:  starting context for the next IA session
 UPDATED: 2026-10-18
 CONTACT: Jeff Nye
```

resume sha b132ddcd-8a8f-43e3-85df-aaf963767a2e

The session reviewed the TD#179 plan in tmp_179.md against the RTL
and the XiangShan reference in ./xiangshan. It ended with two task
files, prompts/BP-139.md and prompts/BP-140.md. Read those for
content; read this for state, decisions and traps.

---

## 0. Where the work is

TD#179: every branch must be predicted at every slot count
(requirement, Jeff, 2026-10-18; restates BP-128 D2).
NUM_PRED_SLOTS is prediction bandwidth into the FTQ only.

```
  WRITTEN  prompts/BP-139.md  cluster cut for any unslotted branch
                              (option A) + item C, no table training
                              through another branch's slot
  WRITTEN  prompts/BP-140.md  per-start FTB and uBTB entries + block
                              split at update. Issue after BP-139 is
                              accepted.
  NOT RUN  neither task has been issued
```

---

## 1. Tree state -- do not re-derive this

Tree 138637d on main. tmp_179.md was written against 0599061; no RTL
change is expected between them, but its cited line numbers have
drifted by a few lines. BP-139 Problem 0 re-confirms them.

No RTL, testbench, Makefile or planning file was changed. No
regression was run this session, so this file carries no counts. The
latest counts are in BP-138's Results Capture (274 targets PASS).

Files written this session:

```
  prompts/BP-139.md
  prompts/BP-140.md
  ia_context/ia_handoffs/ia_session_handoff-006.md
```

---

## 2. Context to load, in this order

```
  CLAUDE.md
  planning/PROJECT_STATUS.md       TD#179 entries near lines 36-56,
                                   944, 1047
  prompts/BP-139.md, BP-140.md     the decisions of this session
  prompts/BP-138.md                the jump cut BP-139 generalizes
  planning/arch/ftb_decisions.md   3 (block model), 4.6 (region
                                   sharing), 5.4a, 5.5, 8
  tmp_179.md                       the plan reviewed (untracked)
```

---

## 3. Findings of the review -- do not go hunting

Confirmed in the RTL (tree 138637d):

```
  bp_cluster.sv 1657-1664   slot 0 reads br0, other slots br1; at
                            one slot br1 is read by nothing
  ftb_cntrl.sv 686-692      br1 driven at every slot count
  ubtb.sv 37-39             one slot reports br0 only
  bp_cluster.sv 1033-1040   w_jmp_cut_p2 tests the jump field only
  bp_cluster.sv 1103-1110   w_pft_p2 arms; no arm for a visible br1
  ftq_resolve.sv 283-294    place_slot: lowest free or at-or-after,
                            else the last slot
  ftq_entry.sv 352-353      the placed slot overwrites the occupant
```

Corrections to tmp_179.md:

```
  E1  Section 4 and the section 6 "three conditionals at two slots"
      check: option A cannot reach a third conditional at two slots.
      The FTB has two conditional fields at every slot count, so it
      never stores one. Only a split at update covers it.
  E2  Item C reverses part of the BP-119 ruling (train table
      predictors on first execution, no R2 suppression). It needed a
      stated ruling, not an inference.
  E3  Item C is needed at both slot counts: at two slots an unheld
      branch behind two occupied slots goes to slot 1.
  E4  Not in the plan: the placed slot overwrites the occupant in the
      FTQ entry. Resolution is out of order, so the occupant can
      resolve later and no longer maps.
  E5  "Until the uBTB learns the shortened end" is unestablished.
      fd04 still shows a p2 redirect per pass. BP-139 Problem 0
      traces the mechanism.
```

XiangShan V2 (xiangshan/scala/.../frontend), checked in source:

```
  NewFtq.scala FTBEntryGen  split at update: pftAddr = offset of the
                            branch that falls out; jump bits cleared
  FrontendBundle TableAddr  FTB index and tag from the full start PC
                            above instOffsetBits: per-start entries,
                            no region sharing
  Tage.scala 612-614        no TAGE update while always_taken; a new
                            branch is inserted always_taken
  FTBEntryGen cfi_is_br     conditionals inserted taken-only
  NewFtq.scala 1372         training at commit
```

The 228/228 split contention BP-131 measured comes from pacino's
region-shared entry (ftb_decisions.md 4.6), not from the split.

---

## 4. Decisions this session (Jeff, 2026-10-18)

```
  D1  Training stays at resolve, not commit.
  D2  Previous rulings set aside for the performance estimate.
      Ranking given (estimate, not measured):
        1 per-start entries + split at update + C   highest
        2 A + C + uBTB learns the cut end
        3 A + C
        4 split at update, region-shared, + C       possibly worst:
                                                    pftAddr flips
  D3  Option 1, as two tasks: BP-139 (A + C), then BP-140
      (per-start + split).
  D4  Task files written to prompts/BP-139.md and prompts/BP-140.md.
```

Choices the IA made in the task files, not ruled by Jeff. Flagged to
him at the end of the session; he did not answer them before the
handoff was requested:

```
  C1  PA session field 082 in both.
  C2  Ruling changes attributed to Jeff, 2026-10-18: item C replaces
      BP-119 for the occupied-slot case; BP-140 reopens 4.6 and the
      4.5 tag alternative.
  C3  The placed-slot overwrite fix left to the BP-139 IA as a
      provisional choice. Jeff skipped that question.
  C4  BP-140 keeps the 2+1 entry shape: under the split rule the
      XiangShan shared-last-field shape is an area change only.
  C5  BP-140 keeps track-every-branch (5.2); XiangShan's taken-only
      insert and always_taken bit not adopted.
  C6  BP-140 index and tag split left to its IA, with set pressure
      named and measured.
  C7  tmp_179.md content folded into BP-139's Background; the file is
      not in its manifest.
```

---

## 5. Traps this session hit

```
  T1  THE IA PUT A GIT COMMAND IN A SURVEY (git log) WITHOUT ASKING.
      CLAUDE.md requires asking first. It was not needed: gitStatus
      in the session context and the plan's sha already gave the
      tree. Jeff rejected the call. No git command ran.
  T2  A plan's line numbers are for its tree. tmp_179.md cites
      0599061; the tree is 138637d. Re-confirm before citing.
  T3  The path asked for was a_context/ia_handoffs/; that directory
      does not exist. Written to ia_context/ia_handoffs/, which holds
      001-005.
  T4  examples/fe_demo now builds its default model at
      NUM_PRED_SLOTS = 1 (OBJ) and a 2-slot model (OBJ2). fd09 and
      fd04 at one slot run on the default model. Both task files keep
      fe_demo read-only and run it in a scratch copy.
```

---

## 6. Working method

The task template is templates/TASK_TEMPLATE.md. In a task file the
author fills Task ID, Date, Module, PA session, the Task and Mode
boxes, the Overview, and every PROMPT section. Left as the template
has them:

```
  Run time, Ctx %, Resume sha   Jeff, by hand
  Model                         the implementing IA
  Status boxes                  unticked; the IA states status
                                inside Results Capture
  DISCUSSION                    after the run: console output and My
                                Assessment by Jeff, Claude.ai
                                Assessment by the PA
  RESULTS                       the implementing IA only
```

Results of BP-139 and BP-140 include instructions to modify the
planning files. These go to the PA, with the completed task file, and
the PA applies them. Both task files fix the form: File, Where,
Action, Current, New, Why. Both also list the fe_demo doc figure
changes as a separate block.

Reads outside a task's grants need asking first (Jeff's BP-138
assessment). Both task files say so.

---

## 7. Next actions, in order

```
  1  Jeff reviews C1-C7 and edits the task files if needed.
  2  Issue BP-139.
  3  PA reviews BP-139's Results Capture and applies its planning
     updates.
  4  Issue BP-140. Its Problem 0 checks that BP-139 is in the tree.
```

Next free BP number after these is BP-141.

---

## 8. For the PA

```
  RATIFY   Item C as a change to the BP-119 ruling, both slot counts.
  RATIFY   Reopening ftb_decisions.md 4.6 and the 4.5 alternative for
           BP-140 (per-start entries). 4.6 says it is not reopened
           unless Jeff reopens it; the task file records that he did.
  NOTE     tmp_179.md section 4 overstates option A at two slots (E1).
           Its section 6 check for three conditionals at two slots
           belongs to BP-140.
  NOTE     The fd09 and fe_demo doc figures (tmp_179.md question 3)
           change with BP-139; the task returns the old-to-new list.
  OPEN     tmp_179.md question 4: TD#179 stays open after BP-140 for
           entry shape, uBTB duplicate fill and training point.
           BP-140's Deliverables ask the IA to propose that wording.
```

---

## 9. Document History

```
  2026-10-18  Created at the close of the IA interactive session
              that reviewed tmp_179.md and wrote BP-139 and BP-140.
```
