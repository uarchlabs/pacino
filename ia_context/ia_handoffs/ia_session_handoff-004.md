<!-- SPDX-License-Identifier: Apache-2.0                       -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# IA Session Handoff 004
```
 FILE:    ia_session_handoff-004.md
 SOURCE:  the IA interactive session of 2026-08-19
 STATUS:  starting context for the next IA session
 UPDATED: 2026-08-19
 CONTACT: Jeff Nye
```

THIS FILE POINTS, IT DOES NOT REPEAT. Everything decided in the last
session is written into the planning documents listed in section 2.
Read those for content; read this for state, order and traps.

Note on the series: 001 through 003 predate the bp_cluster phase and
reference tmp_004.md, which became fe_decisions.md. Treat them as
historical.

---

## 0. Where the work is

The FTQ is now SPECIFIED but NOT BUILT.
rtl/core/frontend/ftq/ holds only .gitkeep files.

The BPU is built, green, and unchanged in behaviour by anything the
next session should need to revisit.

---

## 1. Tree state -- do not re-derive this

All 47 bpu Makefile targets green: 18 lint, 22 sim, 7 cov.
Zero Verilator warnings, zero errors.

```
  sim_bp_cluster / cov_bp_cluster   1765 / 0
  sim_loop_pred                     9342 / 0
  sim_ubtb                           259 / 0
  sim_ittage                         211 / 0
  sim_ittage_cntrl                   147 / 0
  sim_ftb                             99 / 0
  sim_sc_cntrl                        98 / 0
  sim_ras                             87 / 0
  sim_sc                              55 / 0
  sim_sc_fast                         52 / 0
  sim_ittage_table                    32 / 0
  sim (tb_bp_pkg)                     29 / 0
  sim_tage_table / cov_tage_table     15 / 0
```

Key parameters after this session:

```
  FTB_BR_POS_BITS  4    2-byte positions, 16 per 32-byte block
  PFTADDR_BITS     5
  POS_OFFSET_BITS  1    derived, granularity
  PC_HASH_SHIFT    2    predictor index hash, NOT granularity
  RESET_VECTOR     40'h00_8000_0000
  bp_ftq_entry_t   224b     bp_ftq_meta_t  421b per slot
```

---

## 2. Context to load, in this order

```
  CLAUDE.md
  planning/PROJECT_STATUS.md        the IA-interactive block is top
  planning/arch/ftq_decisions.md    FTQ behaviour. START HERE for FTQ
  planning/arch/ftq_entry_formats.md    the two entry structures
  planning/interfaces/ftq_bpu_interfaces.md
  planning/interfaces/ftq_ifu_interfaces.md
  planning/interfaces/ftq_backend_interfaces.md
  planning/arch/fe_decisions.md     BPU<->FTQ paths and the
                                    FE / TD-FE / FE-U registries
```

Load a predictor's own decisions/interfaces file only if that
predictor is in scope. Do not load bp_cluster.sv, 1451 lines, unless
editing it.

---

## 3. What moved -- do not go hunting

fe_decisions.md sections 4, 5 and 6 MOVED OUT. The numbers are
RETIRED, not reused, so every "section 7.2" and "section 2.4"
reference still resolves. The stub at section 4 carries the map.

```
  was 4.1  -> ftq_entry_formats.md 2
  was 4.2  -> ftq_entry_formats.md 3
  was 4.3  -> ftq_decisions.md 1
  was 5    -> ftq_decisions.md 2
  was 6    -> ftq_decisions.md 3
```

bp_cluster.md's FTQ Entry Split is now a pointer. The entry was
described in three places and edited in lockstep; that is fixed.

---

## 4. Open work

```
  TD-FE-7   bp_cluster has no rollback TRIGGER input. The
            checkpoints are all inside bp_history (ckpt_gptr /
            ckpt_pptr, FTQ_DEPTH deep); only the index is missing
            on a backend redirect. Two ports, seven bits. SMALL,
            and the obvious next RTL task.
  BP-100    FTB update scheduler. Specification written, NOT RUN,
            not blocked. Creates the first FTQ module.
  ftq_icache   deliberately not defined. Physical; revisit at PD.
  prefetch     deferred, and PD CANNOT undo it.
               ftq_decisions.md 6.1 lists what it forecloses.
  G10       TAGE/ITTAGE meta overload, still TBD.
  CONVENTION  BP-100's Results section carries a Summary only, not
            the full empty subsection skeleton. Deliberate: empty
            headings imply content that does not exist. The
            alternative is every task file carrying the skeleton so
            grep "## Files Modified" prompts/*.md returns all of
            them. UNDECIDED. Whoever runs BP-100 should settle it.
  TD#96     RAS flush behaviour, G24 FTB flush.
```

Next free BP number is BP-102. Next free INFRA is INFRA-013.

---

## 5. Traps this session hit

```
  T1  do_reset() in tb_bp_cluster clears the ITTAGE tables but NOT
      the TAGE tagged tables. Any test added after group G inherits
      their allocations. Group I works around it by making the case
      TAGE-independent. Worth a TD; not opened.
  T2  Bind assertion files BY MODULE NAME, never by instance name.
      TD#109 is the precedent: bound to an instance, instantiated
      by nothing, warned about by nothing under -Wall.
  T3  The BPU tree has NO concurrent SVA. Its three assert files
      are procedural, simulation-only. ftq_decisions.md 5.7.4
      specifies the first five properties.
  T4  Prove every new check CAN fail by mutation. This project has
      twice shipped checks that could not: a $isunknown test on a
      two-state model, and seven testbenches returning exit 0 on
      failure.
  T5  No git access was granted last session, so NO DIFF was ever
      taken. The file lists in the BP-098/099/101 Results sections
      come from tracking, not from a tool. Verify with
      git diff --stat if that matters.
```

---

## 6. Working method that held up

Two rules earned the hard way, both now in PROJECT_STATUS:

- A parameter name must carry ONE quantity. BP-098 exists because
  INST_OFFSET carried two, and BP-099 was blocked until it did not.
- A predictor training path must not be able to stall the machine.
  Updates are hints; FE-5 promised them like architectural state.

And one about this document class: A STATUS ENTRY POINTS, IT DOES
NOT REPEAT. The PROJECT_STATUS block for this session was first
written at 219 lines against a house norm of 18 to 39, in a file
pasted into every session. Compressed to 56.

Watch tool output volume. It reached 22% of the window last session.
One aggregate line per suite run; grep the log only on failure.

---

## 7. Next actions, in order

```
  1  TD-FE-7. Two input ports on bp_cluster, ORed into the existing
     rollback with priority over the cluster's own. Add checks,
     prove by mutation, rerun all 47. This closes the FTQ
     definition.
  2  BP-100, the FTB update scheduler, as the first FTQ module.
  3  The three IFU-facing entry fields of ftq_ifu_interfaces.md 8
     item 3. Deferred on FE-U7, which is now resolved, so they are
     decidable.
```

---

## 8. For the PA

The PA's start-of-session read set is PROJECT_STATUS + the latest
session_handoff-NNN + CLAUDE.md. THIS FILE IS NOT IN THAT SET, and
no session_handoff-067.md was written. The PROJECT_STATUS
IA-interactive block covers the session; this section lists what
wants PA attention specifically.

```
  RATIFY   FE-5a. FE-5 was amended to permit dropping LOW-value FTB
           updates -- predict-time hit, predicted correctly. The
           alternative was more FTB write ports. Rationale and the
           rejected options are ftq_decisions.md 5.7.
  RATIFY   The two deferrals, and that they are different kinds.
           ftq_icache is physical, PD can undo it. Prefetch is
           functional, PD cannot.
  RATIFY   BP numbering. 098, 099, 101 are complete; 100 is spec
           only. 101 covers work done BEFORE 098 and 099, because
           BP numbers are allocated when the file is written.
  DECIDE   Whether this session's block in PROJECT_STATUS needs a
           session number. It is currently headed "IA interactive
           sessions" rather than Session-0NN; prior numbers count
           PA sessions and there was no PA session.
  NOTE     TD-FE-6 and TD-FE-7 were both found by writing down what
           the FTQ would have to drive, not by running anything.
           Specification found two real defects in green RTL.
```

---

## 9. Document History

```
  2026-08-19  Created at the close of the IA interactive session
              that specified the FTQ. Pointer-based by design; the
              content lives in the files of section 2. Section 8
              added because the IA handoff is not in the PA's read
              set and no session_handoff-067.md exists.
```
