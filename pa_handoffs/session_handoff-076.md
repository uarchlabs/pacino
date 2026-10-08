<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 076
Written by Claude.ai at end of session-075.
Date: 2026-10-08

Read PROJECT_STATUS.md, then this file, then CLAUDE.md.

THE FRONT END RUNS END TO END, TRAINS, AND HAS REACHED A DEFINED END
STATE. Five tasks ran, BP-117 to BP-121. regress.sh ends the session
at 123 targets, all PASS. 19 tb_fe_top programs retire exactly.

BP-121'S RULINGS AND FIXES ARE NOT YET IN THE PLANNING DOCUMENTS.
Recording them is the first job of session-076 (below). Until it is
done, five documents state rules that the RTL no longer follows.

---

## Read This First

### 1. Three recorded rules were replaced in BP-121. The documents still say the old ones.

```
  bp_arb_spec.md 4.5         rules 2-4 (credit arbitration) replaced:
                             a prediction is never delayed; an update
                             is granted when no prediction is
                             presented; after STARVE_THRESH cycles the
                             queue-ready drops for one cycle. TD#39
                             becomes moot.
  bp_history_decisions.md    imprecise history replaced: history is
    3.5                      corrected on a redirect, the checkpoint
                             rewritten, history stops at the first
                             taken slot.
  ftq_backend_interfaces.md  A7 adopted: the backend commits an entry
    A7                       only after every resolution naming it is
                             accepted.
```

### 2. The backend contract grew. Record it before anything is built against it.

A7 (above); a new redirect input bkend_ftq_redir_taken; a new field
ftq_resolve_t.is_rvc (A1, +1 bit); and the rollback history
correction ports ftq_rollback_corr, _n, _tkn, _pbit.

### 3. The task method changed. BP-121 is the template.

In session-075, BP-117 to BP-120 each listed known defects and let the
IA change only the files those fixes needed, so every run ended with
new findings it was not allowed to fix, and each became the next
task. Jeff's ruling after BP-120 (recorded in PROJECT_STATUS):

```
  1  The IA may change anything under rtl/core/frontend/, tests,
     Makefiles and tb_fe_top programs, each fix with a check that
     fails before it.
  2  Packages may change, each listed with its reason.
  3  The git calls tools/regress.sh makes are granted; no other.
  4  Design choices go to Jeff in session. If he does not answer,
     the IA takes its recommended option, marks it PROVISIONAL and
     continues.
  The task is written as an end state, not a defect list.
```

BP-121 ran that way: 16 defects fixed, 9 decisions answered in
session, nothing carried except by ruling. It took 4 hours and one
IA compaction; Jeff will analyse it offline as a case study for
larger tasks. CLAUDE.md still states the narrower read and write
limits; BP-121 overrode them in the task. Whether CLAUDE.md should
state the method is open (ask Jeff).

---

## Session Summary

### Rulings by Jeff

```
  BP-117 to BP-119 rulings     recorded in the documents; see
                               PROJECT_STATUS session-075
  update converter             ftq_upd_conv inside the FTQ; readies
                               ANDed (TD#150)
  unmapped resolution          placed in program order, trains every
                               predictor (ftq_entry_formats 3.1)
  FTB/uBTB field position      kept only for the same position
                               (ftb_decisions 5.5)
  RAS next-on-stack link       reverses session-050's simple buffer
                               (ras_decisions 3.2)
  task method                  above
  BP-121 in session            TD#162 hold p0 before an FTB update;
                               TD#163 carried way checked both ways;
                               TD#164 rvc bit, RAS pushes jump PC+2/4;
                               RAS wrap links to BOS; arbitration;
                               keep 4.6 (TD#168); history corrected;
                               A7
  loop predictor (after        read-before-write allowed, its table
    BP-121; reverses BP-121    is flops; single cycle, no bubble;
    decision 6)                slot 1 wins on a shared entry; a
                               same-cycle prediction sees the old
                               value; each prediction carries its
                               iteration number; speculative
                               iteration count built with it (TD#7,
                               LI4). Physical design bounds the entry
                               count; the FMAX cost is accepted.
                               TD#169
```

### Tasks run

```
  BP-117  C5, C6, C19; ifu_rvc_exp checked against LLVM, 0
          mismatches. TD#146 closed
  BP-118  TD#113, TD#134; ibuf, ITLB, PMP/PMA checker, decode on
          ifu_pd_pkt_t, fe_top. TD#150-155 opened
  BP-119  ftq_upd_conv, RETURN_CALL, rvc_expander retired, LB_RD_MAX,
          uBTB jump taken, IL-7; placement of unmapped resolutions
          ruled in session. TD#156-160 opened
  BP-120  FTB/uBTB position, FTB trained once, one slot per
          resolution, RAS link, TD#155. TD#161-168 opened
  BP-121  end-state task: 19 programs, 16 defects, 9 decisions.
          TD#161-164, 166, 167 closed; TD#169, 170 opened
```

### Found, and worth keeping

- Every new tb_fe_top program has exposed defects. Programs are the
  discovery tool; unit tests were green throughout.
- Predictor tables carried across programs in one simulation gave
  order-dependent numbers. sim_fe_top now runs one simulation per
  program; the no-+PROG mode still carries tables.
- The IA's "reverted fix fails a check" table (BP-121 m01-m15) is
  the evidence standard that worked.

### Documents changed this session

Every file below is in check_planning.sh with its new checksum.

```
  PROJECT_STATUS.md
  arch:   bp_arb_spec, dcd, fe, ftb, ftq, ftq_entry_formats, ibuf,
          ifu, itlb, mmu, ras
  intf:   ftb, ftq_backend, ftq_bpu, ftq_ifu, ifu_ibuf, itlb_ifu,
          itlb_l2tlb, ras, ubtb
```

---

## Next session (076)

### Job 1: record BP-121. Documents first, no task.

Source: prompts/BP-121.md, "Decisions made" and "Other Notes"
(Planning text I would change). Section by section:

```
  ftb_decisions.md     4.6 / R-1 a field past the start's visible
                       jump is hidden (D4). 5.5 and 8: jump field
                       rvc bit, entry width +1; RAS push and block
                       fall-through are jump PC + 2/4 (D3). 9 FTB-5:
                       TD#162, TD#163, TD#164 as ruled and built
  ftb_interfaces.md    ftb_upd_jmp_rvc_u0, ftb_jmp_rvc_p2;
                       IC-FTB-03 push source; IC-FTB-10 carried-way
                       check (TD#163)
  ftq_bpu_interfaces   4a p3 gated on the FTB answer (D1); 6
                       successors chained from the highest slot,
                       no redirect after a taken slot (D5, D15);
                       history correction ports (D14)
  fe_decisions.md      FE-14 squash as built (D8, D9); FE-10 p1
                       slots in position order (D12); 7.2 the
                       loop predictor ruling
  ras_decisions.md     1 and 4.3: no restore on the cluster's own
                       redirect (D9); p3 repair uses p3
                       reachability (D10); 3.2 wrap to BOS
                       confirmed (drop "provisional")
  ras_interfaces.md    ras_p2_keep port (D8); IC-RAS-11 as above
  bp_arb_spec.md       4.5 replaced (decision 5)
  bp_history_          3.5 replaced (decision 8, D14, D16)
    decisions.md
  ftq_backend_         A7; bkend_ftq_redir_taken; is_rvc in A1
    interfaces.md
  ftq_entry_formats    slots rewritten by every resolution, cleared
                       above a resolved end; pft_addr rewritten at
                       resolution of a taken jump (D2, D3)
  ftq_decisions.md     ftq_npc holds p0 before an FTB update (D7)
  loop predictor docs  LI4 / TD#7: the ruling above
  bp_cluster.md        check against D5, D6, D10, D12-D16
  PROJECT_STATUS       module rows for bp_cluster, ftb_cntrl, ras,
                       ftq_resolve, ftq_entry, ftq_npc, bp_history,
                       tage, ittage
```

FILES THE PA DID NOT HAVE IN SESSION-075; ask Jeff for them:
bp_history_decisions.md, the loop predictor's planning document(s),
bp_cluster.md. Read each in full before editing it.

### Job 2: BP-122, written as an end-state task

Candidate scope (Jeff to confirm):
```
  TD#169  the loop predictor, as ruled: used in lp and loops,
          loop exits predicted after warm-up
  TD#170  properties for the BP-121 fixes in ftq_resolve, ftq_entry,
          ftq_npc, ras, bp_history, each fired by a mutation
  -       delete decode/verilator/sim_main_predecode.cpp (unused)
  -       predictor table reset between programs in the all-programs
          simulation, or remove that mode
  -       regression leaves bpu/obj and bpu/waves.fst in the tree
```
Use BP-121's grants and decision rules. Write it after Job 1, so the
task's citations point at current rules.

### Open, for Jeff

- TD#168: keep 4.6 stands (ruled). It is now the largest accuracy
  loss (deep 91 of 146 mispredicts after warm-up, nest 41/62,
  region 25/37, coro 25/32, recur 21/33). Do not re-raise unless
  Jeff does; the numbers are recorded.
- Whether CLAUDE.md should state the end-state task method.
- TD#165, two return-call repair pairings, not reached by any
  program.

### Comment-only RTL, still carried (from session-074)

```
  ftq_ifu.sv, above the flush always_comb; ftq_ptr.sv 403-405;
  ftq_meta.sv and tb_ftq_meta.sv "421 bits"; tb_ittage_cntrl.sv
  chk38, chk57; sc.sv 30-32, 148; tb_ftq_resolve.sv 174, 525;
  ftq.sv // OLD: lines from BP-117
```
BP-121 changed several of these files; check whether any were fixed.

### Numbers

```
  next free BP     BP-122
  next free INFRA  INFRA-014
  next free TOOLS  TOOLS-007
  next free TD     TD#171
```

---

## IA behaviour, recorded

- BP-119 and BP-120 read outside their manifests and reported it.
  The manifests were too narrow (PA error); BP-121's read grant
  removed the cause.
- BP-120 ran tools/regress.sh, whose git calls the task forbade
  without a grant. The task created the conflict (PA error); BP-121
  granted those calls.
- BP-121 corrected its own in-session numbers when it found they
  came from a simulation that carried tables across programs, and
  added failing checks for two fixes it found had none. Both
  unprompted.

---

## Postmortem Record -- PA performance (session-075)

1. TASKS BUILT TO ITERATE. BP-117 to BP-120 each listed known defects
   and fenced the IA to the files those needed, so each run's
   findings became the next task. Jeff: "The point of this was to do
   this all at once. Why are we iterating?" The PA then proposed more
   up-front rulings, which had been the method all along. Fixed by
   the end-state method, which Jeff ruled and BP-121 proved.

2. TASKS THAT COULD NOT BE DONE WITHOUT BREAKING A CONSTRAINT.
   BP-120 required regress.sh and forbade git without a grant, after
   Jeff had granted those calls in BP-119's run. BP-119's manifest
   was too narrow for the converter. BP-119 scoped TD#155 without
   the decode_pkg change its fields need.

3. STATEMENTS FROM DOCUMENTS, NOT THE RTL. BP-118 described
   bpu_blk_ras_p2 as built (it was not), took RETURN_CALL and
   dual_pred_en from the documents, listed rvc_expander for deletion
   without checking its users, left itlb_l2t_vpn at 27 bits. BP-117
   named Spike as an oracle without checking.

4. JARGON AND LENGTH. Jeff: "use proper English." Answers that
   needed a paragraph got sections; a decision list included an item
   (entry count) the PA did not need.

5. CONTEXT. The session compacted once; whole files and whole
   results were read where sections would do.

What worked: checksum verification of every delivered file against a
scratch tree; a single replace helper that fails on any anchor not
found exactly once; recording each ruling in its owning document in
the same session; and BP-121's grants, which let the IA finish.
