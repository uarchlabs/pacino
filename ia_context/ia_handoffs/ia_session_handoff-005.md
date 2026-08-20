<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# IA Session Handoff 005
```
 FILE:    ia_session_handoff-005.md
 SOURCE:  the IA interactive session of 2026-08-20
 STATUS:  starting context for the next IA session
 UPDATED: 2026-08-20
 CONTACT: Jeff Nye
```

THIS FILE POINTS, IT DOES NOT REPEAT. Everything decided last
session is in the planning documents of section 2 and in the five
task files BP-100 and BP-102 through BP-105. Read those for content;
read this for state, order and traps.

Continues IA-004 directly. Same series, same tree, one day later.

---

## 0. Where the work is

THE FTQ SPECIFICATION IS COMPLETE. Nothing blocks writing RTL.

The unit is no longer empty: `rtl/core/frontend/ftq/` has rtl/, tb/,
a Makefile and a README, and one of its eleven modules is built.

```
  BUILT     ftq_ftb_sched.sv + its bound SVA (BP-100)
  SPECIFIED the other ten. ftq_decisions.md 7 names them.
```

---

## 1. Tree state -- do not re-derive this

All 47 bpu targets green: 18 lint, 22 sim, 7 cov.
All 2 ftq targets green.
Zero Verilator warnings, zero errors, in both units.

```
  sim_bp_cluster / cov_bp_cluster   1795 / 0    was 1765
  sim_history / cov_history        19224 golden fold comparisons
  sim_loop_pred / cov_loop_pred     9342 / 0
  sim_ubtb / cov_ubtb                259 / 0
  sim_ittage                         211 / 0
  sim_ittage_cntrl                   147 / 0
  sim_sc_cntrl                        98 / 0
  sim_ftb                             99 / 0
  sim_ras                             87 / 0
  sim_ftq_ftb_sched                   67 / 0    NEW UNIT
  sim_sc                              55 / 0
  sim_sc_fast                         52 / 0
  sim_ittage_table                    32 / 0
  sim (tb_bp_pkg)                     29 / 0
  sim_tage_table / cov_tage_table     15 / 0
  sim_sc_table, _fast                  6 / 0 each
  sim_sc_brimli, _fast                 7 / 0 each
  sim_tage, _fast, _tasks, _manual    pass, no numeral
```

ONLY sim_bp_cluster MOVED, 1765 -> 1795, and that is BP-102's group
J. Everything else is identical to the IA-004 numbers.

New parameters and structures this session:

```
  ftb_upd_t         the 14 FTB update payload fields, one struct
  ftq_ftb_sched     NUM_UPD_CHAN = 2, one-deep skid
  per-entry status  3 flop vectors x FTQ_DEPTH = 192 bits, and
                    NOT in either SRAM. entry_formats 4.1 says why.
  RC_UNSPEC         was RC_RESERVED
  bp_cluster        + ftq_rollback_val, ftq_rollback_idx
```

Entry sizes are UNCHANGED: fast 224b, slow 421b/slot, 68,224b.

---

## 2. Context to load, in this order

```
  CLAUDE.md                       READ THE NEW SECTION AT THE END
  planning/PROJECT_STATUS.md      the IA-interactive block is top
  planning/arch/ftq_decisions.md  FTQ behaviour. START HERE.
                                  Section 7 is the module list.
  planning/arch/ftq_entry_formats.md
  planning/interfaces/ftq_bpu_interfaces.md
  planning/interfaces/ftq_ifu_interfaces.md
  planning/interfaces/ftq_backend_interfaces.md
  planning/arch/fe_decisions.md   FE / TD-FE / FE-U registries
```

Load a predictor's own decisions file only if that predictor is in
scope. Do not load bp_cluster.sv, 1584 lines, unless editing it.
`rtl/core/frontend/ftq/README.md` is the short version of the unit.

---

## 3. What is new -- do not go hunting

```
  ftq_decisions.md 7          MODULE DECOMPOSITION. Eleven
                              modules, ftq.sv purely structural.
  ftq_entry_formats.md 4      per-entry fetch status, and 4.4 the
                              generation bit
  ftq_ifu_interfaces.md 6.1   stale writeback rejection
  ftq_backend_interfaces.md   5.1 RC_UNSPEC; 8 rewritten to the
                              built rollback input
  ras_decisions.md 4.4        rewritten; 4.4.1 and 4.4.2 are new
  fe_decisions.md 11          FE-14 added
```

Two Document History sections were renumbered to make room:
ftq_entry_formats 4 -> 5, ftq_decisions 7 -> 8. Nothing referenced
either. Section numbers are otherwise RETIRED, not reused.

---

## 4. Open work

```
  FTQ RTL   The whole point. Ten modules unbuilt. Section 7 of
            ftq_decisions is the partition and the rule behind it.
  G10       TAGE/ITTAGE meta overload, TBD at implementation.
            Same family as TD-FE-2 and collapsible later.
  G25       ftb_fastpath_en source: CSR, tie or runtime. TBD.
  TD-FE-3   pc and per-slot target are 40 bits; 39 suffice under C,
            35 with block alignment. A width optimisation.
  TD-FE-4   pred_src diagnostic, FE-U3 confidence unconsumed.
            Drive zero; BP-101 is the precedent.
  ftq_icache / PREFETCH   deliberate deferrals. PD can undo the
            first, not the second.
  RC_UNSPEC has no producer and cannot until there is a backend.
  PARKED    One unverified RAS observation, restore-versus-replay
            on a redirect. NOT blocking, NOT confirmed reachable,
            and deliberately parked. Do not re-raise it as part of
            other work; see section 6.
```

CLOSED THIS SESSION: TD-FE-7, TD-FE-8, TD-FE-1 in full, RAS-3,
TD#96, G24, IC-FTB-07, IC-FTB-09, IC-SC-06, IC-SCT-03, G9, G23,
bp_arb_spec item E.

Next free BP number is BP-106. Next free INFRA is INFRA-013.

---

## 5. Traps this session hit

```
  T1  --assert IS MANDATORY for concurrent SVA. Without it
      Verilator parses the properties and generates NOTHING, so
      they never fire and look identical to properties that pass.
      Both ftq targets pass it. Prove new properties by mutation.
  T2  do_reset() in tb_bp_cluster still does NOT clear the TAGE
      tagged tables. tage_clear_all() now EXISTS and group J uses
      it, but do_reset does not call it, so groups A-I are
      unchanged. Measured: removing the clear changed nothing
      today, so it is defensive, not load-bearing.
  T3  A 2-MINUTE COMMAND TIMEOUT LOOKS EXACTLY LIKE A HANG in a
      log tail. One mutation run was misread as hung; it was the
      window expiring during compilation. TD#111 was a real hang,
      so the two are worth distinguishing before reporting.
  T4  -Wno-UNUSED is in VER_FLAGS project-wide and HIDES DEAD
      PORTS on synthesisable modules. ras_flush_val is declared on
      ras.sv and read by nothing. Not opened as a TD, by decision.
  T5  Verilator on PATH is 5.020. The Makefiles use
      $(RVA_ROOT)/tools/bin/verilator, which is 5.048. Check which
      one a bare command picked up.
  T6  SYNCASYNCNET fires on any module with an async reset AND
      concurrent SVA, because rstn appears in every disable iff.
      Suppress per target, as lint_bp_cluster does.
  T7  NO GIT ACCESS was granted this session either. Files
      Modified lists in every task file come from tracking, not
      from a diff. Same as IA-004 T5, still unverified.
```

---

## 6. Working method -- read this before answering anything

CLAUDE.md GAINED A NEW SECTION, "Guidance during interactive
sessions", added by Jeff during the session. It is short and it is
there for cause. Both rules were earned:

- Check whether a topic is CLOSED before raising it. A closed item
  that surfaces during unrelated work is not a finding.
- No unnecessary jargon or picturesque phrasing.

The first rule exists because the RAS flush question was re-raised
repeatedly across sessions, including once AFTER the task that
closed it, by the same session that wrote the closure. Documentation
alone did not stop it, because the recurrence came from exploring
RTL rather than from reading the documents.

Two rules from the work itself:

- SINGLE SOURCE, EVERYTHING ELSE POINTS. A fact copied into a
  second document goes stale in the copy. Eight sites restated the
  RAS flush decision and seven had drifted. The same audit later
  found the registry ranges and the PROJECT_STATUS G-table drifting
  for the same reason.
- A SWEEP MUST BE MECHANICAL. The first tree-wide sweep in BP-105
  was reported complete and had missed five sites. Grep the whole
  tree and paste the result; do not eyeball it.

Tool output stayed near 3% of the window this session against 22%
last session, by printing ONE aggregate line per suite run and
grepping logs only on failure. Keep doing that.

---

## 7. Next actions, in order

```
  1  ftq_entry.sv and ftq_status.sv. The storage, and the module
     that proves the flop-vs-SRAM split of entry_formats 4.1 is
     real. Smallest useful pair.
  2  ftq_ptr.sv. Three pointers, FQ-1, full and empty, rewind.
     ftq_decisions 5.1 to 5.5.
  3  ftq_npc.sv. The next-PC register, the priority mux and the
     redirect arbitration, ftq_decisions 4.
  4  ftq.sv last, once there is something to wire. It must stay
     structural -- no always block, no state.
```

Each is a BP task with its own tb and Makefile targets. The ftq
Makefile has the pattern; follow lint_ftq_ftb_sched.

---

## 8. For the PA

The PA's start-of-session read set is PROJECT_STATUS + the latest
session_handoff-NNN + CLAUDE.md. THIS FILE IS NOT IN THAT SET, and
no session_handoff-0NN was written. The PROJECT_STATUS IA block
covers the session; this section is what wants PA attention.

```
  RATIFY   FE-14, a flush is a redirect. Closes TD#96, G24,
           IC-FTB-07, IC-SC-06, IC-SCT-03 and bp_arb_spec item E
           by DECISION rather than by protocol. Evidence is
           XiangShan having no flush port on any predictor.
  RATIFY   The FTB flush gate in ftb_cntrl.sv was RATIFIED rather
           than removed, resolving a document-versus-tree
           disagreement in the tree's favour.
  RATIFY   RC_RESERVED -> RC_UNSPEC. Alternatives and reasons for
           rejection are in BP-105.
  RATIFY   The FTQ module decomposition and its one rule: every
           piece of state has exactly one owner module.
  RATIFY   Per-entry status as FLOPS outside both SRAMs.
  DECIDE   Still unresolved from IA-004: whether the IA block in
           PROJECT_STATUS needs a session number.
  NOTE     BP-100, BP-103, BP-104 and BP-105 were written
           RETROSPECTIVELY and each says so in its header. BP-102
           was specified before it ran. The distinction matters
           when reading them side by side.
  NOTE     Specification found defects in green RTL again. BP-100
           found P1 and P4 of ftq_decisions 5.7.4 mutually
           unsatisfiable -- one demanded a registered output, the
           other combinational, on the same signal.
```

---

## 9. Document History

```
  2026-08-20  Created at the close of the IA interactive session
              that built the first FTQ module and closed flush.
              Pointer-based, following IA-004. Section 6 is longer
              than its counterpart in 004 because CLAUDE.md gained
              interactive-conduct rules during the session and the
              next session must know why they exist.
```
