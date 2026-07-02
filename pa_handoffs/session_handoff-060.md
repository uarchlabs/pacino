<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 060
Written by Claude.ai at end of session-059.
Date: 2026-07-02

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-059 took SC from "sc.sv not written" to a complete, green SC
unit: sc.sv (structural top) landed, the br_imli_mode runtime port was
converted to a compile-time parameter, and the pre-existing tage
elaboration break was investigated and scoped (not yet fixed). The
next session fixes tage.

The SC authority doc:
  planning/arch/sc_decisions.md (Draft, updated session-059)
The arbitration authority doc:
  planning/arch/bp_arb_spec.md (Draft, session-057, untouched)

---

## Read This First

SC is now complete and green at the sc.sv level (BP-078), and the
br_imli_mode cleanup (BP-079) is done. The remaining SC-unit item is
sc_coverage_plan.md (not written).

The next task is NOT SC. It is the tage struct reconciliation, scoped
this session by the gated BP-080 investigation. tage.sv and
tage_cntrl.sv do not elaborate on the committed baseline; the fix is
understood and scoped (see Open Work). The tie-off policy for the
ungenerated SC-facing fields was decided this session (see Decisions).

sc_decisions.md WAS edited this session (section 12 br_imli_mode
parameter spec). bp_arb_spec.md was not touched.

---

## Session Summary

1. BP-078 -- sc.sv structural top + tb_sc.sv + tests. Landed green:
   sim_sc 55/0, sim_sc_fast 52/0, lint_sc 0/0. sc.sv instantiates
   sc_cntrl, a generate loop of sc_table (ST0-ST3), sc_brimli (ST4),
   and one sram_init sized to ST4 (1024x6, 10b addr). The task was
   authored against the real unit RTL, which surfaced four items the
   doc-only version could not: index-bus width adapters (9b ST0-ST3
   idx vs 10b SC_MAX_IDX_WIDTH bus -- zero-extend up, slice down),
   arb-status port stubbing (no SC UQ in this unit; sc_uq_not_full=1,
   deferred to bp_cluster TD#73/#94), a single sram_init sized to the
   largest table, and the br_imli_mode port gap (item 2). IA added
   -Wno-SYNCASYNCNET (sram_init async reset; same as tage/ittage
   tops) -- ratified.

2. br_imli_mode decided: compile-time module parameter, NOT a runtime
   port. Consumed only by sc_brimli (get_br_imli_idx); sc_cntrl only
   routed it. Parameter lives on sc_brimli (BR_IMLI_MODE, default
   IDX_IMLI_PHR); sc.sv exposes SC_BR_IMLI_MODE and passes it down;
   sc_cntrl drops the input and the t_br_imli_mode passthrough. See
   Decisions.

3. sc_decisions.md updated (session-059): section 12 gained the
   "BrIMLI index mode -- compile-time parameter" subsection; section 9
   st4_index gained a one-line note; a session-059 history line was
   added. Section-5 FIXME and the section-1 [NOT WRITTEN] markers were
   left untouched (out of scope; both are still stale -- see
   bookkeeping).

4. BP-079 -- br_imli_mode port->parameter conversion. Landed green:
   sim_sc 55/0, sim_sc_fast 52/0, sim_sc_brimli 7/7 (+fast),
   sim_sc_cntrl 98/0, all SC lints 0/0. sc_brimli gained BR_IMLI_MODE
   and dropped its port; sc_cntrl dropped both br_imli_mode ports and
   the assign; sc.sv gained SC_BR_IMLI_MODE and passes .BR_IMLI_MODE
   to u_st4. tb_sc_brimli now covers all three modes via three
   parameter-override DUT instances (u_dut / u_dut_phr / u_dut_imli).
   No package edits. Default-mode equivalence vs BP-078 confirmed. The
   enumerated tage waiver (TD#94/#95) worked -- the IA did not
   adjudicate the pre-existing break. (Task was authored as BP-079a;
   Jeff renumbered to BP-079.)

5. BP-080 -- gated (report-first) investigation of the tage break.
   Phase 1 executed and STOPPED as designed; no files modified. The
   Phase-1 report corrected the task hypothesis (see Decisions /
   Open Work) and scoped the fix. Marked complete-to-scope-next-task.

6. Decision recorded: the ungenerated SC-facing tage_pred_meta_t
   fields are tied to zero (instantiate, tie to constant) and reported
   as owed real generation; TD#87/#88 generation is NOT implemented in
   the reconciliation task. See Decisions.

---

## What Was Accomplished

  - rtl/core/frontend/bpu/rtl/sc.sv -- written, green (BP-078).
  - rtl/core/frontend/bpu/tb/tb_sc.sv + sim_sc / sim_sc_fast targets.
  - sc.sv/sc_cntrl/sc_brimli br_imli_mode port -> parameter (BP-079).
  - tb_sc_brimli.sv three-mode parameter-instance coverage (BP-079).
  - planning/arch/sc_decisions.md -- section 12 br_imli_mode parameter
    spec, section 9 note, history line (session-059).
  - BP-080 Phase-1 tage-break scoping report (no RTL changed).
  - SC unit is complete and green end to end below the cluster.

---

## Decisions (session-059)

### br_imli_mode is a compile-time module parameter

Not a runtime port. sc_brimli holds `parameter br_imli_mode_e
BR_IMLI_MODE = IDX_IMLI_PHR`; sc.sv holds `parameter br_imli_mode_e
SC_BR_IMLI_MODE = IDX_IMLI_PHR` and passes it to the ST4 instance;
bp_cluster sets SC_BR_IMLI_MODE at the sc.sv instantiation for a
non-default perf build. sc_cntrl does not carry the mode at all. The
default is on the module (propagated by parameter), not in a package.
sc_decisions.md section 12 is the authority. Implemented by BP-079.

Correction on record: an earlier version of the sc_decisions.md edit
and the BP-079 task carried a false rationale (that an enum-typed
default "cannot" be a bp_defines_pkg parameter because of import
order). That claim was wrong and was removed from both files. The
placement of the default on the module stands as a plain choice, not a
constraint. See Postmortem.

### tage struct reconciliation -- tie-off policy (RECORD THIS)

The session-057 standalone-SC struct change (cond_pred_* retired;
tage_pred_meta_t gained SC-facing fields) left tage un-back-filled.
The reconciliation task will:

  - Retype the two live tage.sv FIFOs off the retired wrappers, NOT
    delete them (they are live storage -- see below).
  - Delete the genuinely-dead tage_high_conf logic.
  - For every tage_pred_meta_t field TAGE does not yet generate
    (tage_pred_medium, tage_provider_ctr, tage_extd_ctr, and
    tage_pred_weak if re-added): INSTANTIATE AND TIE TO A ZERO
    CONSTANT, and report each as owed real generation logic.
    tage_pred_strong is already generated and is kept.

Real generation (the strong/medium/weak decode of TD#87 and the
provider_ctr/extd_ctr of TD#88) is NOT implemented in this task. The
tie-off is only to make tage elaborate/green and drive the outputs to
a defined value; the real logic is deferred to the TD#87/#88 tasks.

Key correction from the BP-080 Phase-1 report (my BP-080 hypothesis
was half-wrong): cond_pred_meta_t / cond_pred_upd_inp_t are NOT dead
code. They are the element type of two LIVE FIFOs:
  - tage.sv uq_data_mem (update queue), read into cntrl_upd_inp_u0 ->
    tage_cntrl update port.
  - tage.sv rb_meta_mem (response buffer), read into tage_pred_meta_p2
    -> module output port.
What is dead is only the merged-model WRAPPER subfields (.sc,
.sc_valid, .resolved_taken, .cond_mispredict) -- written then never
read. The fix is therefore a RETYPE, not a delete: change the FIFO
element type to tage_upd_inp_t / tage_pred_meta_t and collapse the
per-subfield writes to whole-struct writes. Behavior is bit-identical.
This is why the gated report-first structure was used, and it earned
its place.

---

## Open Work

### NEXT TASK -- tage struct reconciliation (scoped, ready to write)

Proposed BP-081 (Jeff renumbers as he sees fit). All line numbers are
from the BP-080 Phase-1 report and MUST be re-derived in the task
(they drift). Scope is tage-only.

RTL -- tage.sv:
  - uq_data_mem: cond_pred_upd_inp_t -> tage_upd_inp_t. Collapse the
    5 subfield writes to `uq_data_mem[..][s] <= tage_upd_inp_u0[s];`
    and the read to `cntrl_upd_inp_u0[s] = uq_data_mem[..][s];`.
  - rb_meta_mem: cond_pred_meta_t -> tage_pred_meta_t. Collapse the
    3 subfield writes to `rb_meta_mem[..][s] <= cntrl_pred_meta_p2[s];`
    and the read to `tage_pred_meta_p2[s] = rb_meta_mem[..][s];`.

RTL -- tage_cntrl.sv:
  - Delete the tage_high_conf write and the now-dead high_conf_p1
    decl / reset / compute (genuinely dead; only consumer was the
    removed-field write).
  - Tie the ungenerated SC-facing fields to zero and report each:
    tage_pred_medium, tage_provider_ctr, tage_extd_ctr (all present in
    the struct, unpopulated). Keep tage_pred_strong (already
    generated).

TB -- tb_tage_manual.sv:
  - Remove the 4 tage_high_conf debug taps (the field is gone).
  - tb_tage.sv and tage_assert*.sv had 0 references (no edit).

OPEN SUB-QUESTION for the task (decide before writing it):
  tage_pred_weak is COMMENTED OUT of bp_structs_pkg.sv, so tying it to
  zero requires re-adding the field first (a package edit). sc_cntrl
  consumes only tage_pred_strong and tage_pred_medium -- NOT weak. So
  either (i) re-add tage_pred_weak and tie it to zero (package touch,
  keeps TD#87's field set whole), or (ii) leave tage_pred_weak out of
  scope until the TD#87 generation task. This determines whether the
  reconciliation task touches the package. Recommend (ii) -- keep the
  task tage-RTL-only and no package churn, add tage_pred_weak with its
  generation in the TD#87 task -- but it is Jeff's call.

Verify (task success = tage GREEN, not waived):
  lint_tage_cntrl, lint_tage, sim_tage, sim_tage_fast, sim_tage_tasks,
  sim_tage_manual all green; full bpu regression shows no NEW breakage;
  SC targets green as a cross-check (must be unaffected). sim_tage_
  manual is not in `all` -- run it explicitly.

Then the real TD#87 (strong/medium/weak generation; SC consumes
medium) and TD#88 (provider_ctr/extd_ctr generation; SC consumes
extd_ctr) remain as their own follow-on tasks -- the tie-off only
unblocks elaboration.

### SC -- remaining unit item

  - verification/sc_coverage_plan.md -- not written.
  - sc_cntrl_ctr_update_rules.md -- optional, write at coverage/tb
    time citing sc_decisions section 10.

### SC -- prerequisites (gate cluster integration, not unit work)

  - #87/#88 TAGE generates tage_pred_medium / tage_extd_ctr (the
    tie-off above is the interim; real values needed at integration).
  - #89/#90 FTB supplies branch_range[15:6] and per-slot backwards
    sign to sc_upd_inp.
  - #91/#92 bpc routes PC p0->p2 (inp_pc_p2) and phr[9:0] (sc_phr_p2).
  - #84 end-to-end fold check extends to SC ST1-ST3.
  - br_imli_mode source: now a parameter; bp_cluster sets
    SC_BR_IMLI_MODE at the sc.sv instantiation if non-default.

### PROJECT_STATUS bookkeeping (accumulated -- not yet applied)

Carried from handoff-059 and grown this session. None applied yet:
  - Add TD#98 (dual-slot shared scalar state; drafted handoff-059).
  - SC decomposition section still reads "RTL not started" and lists
    sc_interfaces / sc_table_interfaces / sc_table_hash_rules /
    sc_tb_decisions as [NOT WRITTEN] -- all four exist; sc_table /
    sc_brimli / sc_cntrl / sc.sv are written and green. Update.
  - Module Status table: add sc_table, sc_brimli, sc_cntrl, sc rows
    (Complete, unit/integration green).
  - Record the tage break + its scoped fix under TD#94 (cond_pred_*
    retype) and TD#95 (tage_high_conf delete + tie-off), referencing
    the BP-080 finding (retype-not-delete).
  - sc_decisions.md session-059 edit reflected in status.
  - Header checkboxes on BP-075/075a/076/077/078/079 task files
    unticked in IA output -- set manually. BP-080 marked complete-to-
    scope.
  - sc_decisions.md section-1 [NOT WRITTEN] markers and section-5
    FIXME are stale -- clean in a doc pass.

### Carried infra (unchanged; Jeff's priority call)

  - bp_history close-out: s6.6 sha (#83); BP-072/073 status
    checkboxes; retire versions/bp_history.sv.
  - #43 ITTAGE CTR 3b->2b, #75 sim_ittage_fast, #77 path scrub,
    #67/#68 sram_init non-fast, #38 covergroup #7099 re-check.

---

## SC State: COMPLETE at unit level (sc.sv green); tage back-fill next

sc_table, sc_brimli, sc_cntrl, and sc.sv are written and green.
br_imli_mode is a compile-time parameter. Remaining SC-unit item is
sc_coverage_plan.md. The next session's work is the tage struct
reconciliation (tie-off policy above), then the TD backlog.

---

## Next Session (060)

At session start Jeff will paste:
  PROJECT_STATUS.md
  session_handoff-060.md (this file)
  CLAUDE.md
  rtl/.../tage.sv
  rtl/.../tage_cntrl.sv
  rtl/.../bp_structs_pkg.sv
  rtl/.../bp_defines_pkg.sv
  rtl/.../tb/tb_tage_manual.sv
  rtl/.../Makefile
  (the BP-080 Phase-1 report, for the line-level fix map)

Start by settling the OPEN SUB-QUESTION (tage_pred_weak: re-add+tie vs
defer) -- one decision -- then generate the tage reconciliation task
(BP-081): retype the two live FIFOs off cond_pred_*, delete dead
tage_high_conf logic, tie the ungenerated SC-facing fields to zero and
report them, remove the 4 tb taps, prove the tage suite green. The
BP-080 report gives the file:line map; re-derive line numbers in the
task. Do not implement TD#87/#88 generation in this task.

After tage is green, the TD backlog (bookkeeping above, then #87/#88
real generation, then the cluster prerequisites #89-#92) is the path
toward bp_cluster integration.

---

## Postmortem Record -- PA performance (session-059)

Continuing the trend log (052/053 unchecked claims; 054 over-asking;
055 one under-audited line; 056 late-source/imported framing; 057
unsourced number, volume, manufactured hazards; 058 over-asking).
059's dominant failure was asserting a fabricated technical constraint
and defending it.

1. Fabricated SV constraint, in a delivered doc. The PA claimed the
   br_imli_mode default "cannot" live in bp_defines_pkg because
   bp_structs_pkg imports after it (an "import ordering" rule), wrote
   that rationale into sc_decisions.md AND the BP-079 task, then
   defended it twice in chat with further wrong elaboration ("governs
   unqualified name visibility at the point of import") before the
   user supplied the counterexample (`parameter [1:0] DFLT =
   bp_structs_pkg::IDX_IMLI_PHR`, and the unqualified form) twice. A
   scoped `pkg::NAME` reference to an enum constant is legal
   regardless of wildcard-import order; package elaboration is not
   gated by consumer imports. The false paragraph was stripped from
   both files. Worst error of the session: a made-up rule shipped in a
   planning document, and doubled down on. Root cause: theorizing SV
   semantics from memory instead of verifying or staying silent.

2. Manifest built by inference, not from the tree. BP-080 listed
   rtl/.../tage_hash.sv (abandoned per PROJECT_STATUS, not in the live
   build) and put tage_assert.sv at rtl/ instead of tb/. The user
   caught tage_hash.sv directly. Root cause: assembled a
   "comprehensive tage set" without checking each path against
   PROJECT_STATUS / the tree.

3. Authored a design fork instead of raising it, plus a PA aside in a
   task file. BP-078 baked "add a top-level br_imli_mode port" into
   the task and recorded a PA note under the task's "Other Planning
   File Updates" -- the mode was a parameter, and PA observations
   belong in the session, not the artifact. The user corrected both.

4. Date default carried without checking. BP-078/079/080 headers
   stamped 2026.07.01, carried from prior files; today was 2026.07.02.
   User caught it.

What held:
  - The gated BP-080 structure worked exactly as intended: Phase 1
    caught that the PA's "cond_pred_* is vestigial" hypothesis was
    half-wrong (they are live FIFO element types), so the wrong fix was
    never shipped -- the report-first gate absorbed a bad hypothesis.
  - The enumerated tage waiver (BP-079) worked; the IA stopped
    adjudicating the pre-existing break.
  - BP-078/079 landed green on the first IA run; the interface
    cross-check against the real RTL (width adapters, arb stubs) was
    correct and load-bearing.

Pattern to carry into 060:
  - Do not state a technical constraint (SV semantics especially) from
    memory. Verify it against the code/tools or do not assert it. A
    fabricated constraint in a delivered doc is worse than silence,
    and defending it compounds the cost.
  - Build task manifests file-by-file from PROJECT_STATUS / the tree.
    Confirm each path exists and is in the live build before listing.
  - Raise design forks (port vs parameter, etc.) to Jeff; keep PA
    observations in the session, never as asides in task files.
  - Check the real date before stamping task headers.

