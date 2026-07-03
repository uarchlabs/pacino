<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 061
Written by Claude.ai at end of session-060.
Date: 2026-07-02

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-060 fixed tage. BP-081 reconciled the tage RTL to the current
bp_structs_pkg AND generated the SC-facing confidence outputs for real
(TD#87/#88), superseding the tie-off plan from handoff-060. tage now
elaborates and its full suite is green. All seven predictor units are
now written and green at the unit level. The next session builds the
bp_cluster (BPU) top and burns down tech debt.

The SC authority doc:
  planning/arch/sc_decisions.md (Draft, updated session-059)
The arbitration authority doc:
  planning/arch/bp_arb_spec.md (Draft, session-057, untouched)
The BPU cluster summary:
  planning/arch/bp_cluster.md (LOCKED; In progress)

---

## Read This First

tage is fixed and green. BP-081 did more than handoff-060 scoped: Jeff
folded TD#87 and TD#88 into it mid-session, so the SC-facing fields are
GENERATED, not tied to zero. The tie-off policy in handoff-060 is
HISTORICAL -- do not carry it forward.

All predictor units (uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS) plus
bp_history are complete and green at the unit level. bp_cluster (top)
and fetch remain "Not started."

The next session is Jeff's call: build the bp_cluster top level and
close as much tech debt as possible. Jeff wants to START THAT SESSION
WITH FREE CONTEXT -- this session was closed early on purpose to keep
the next one clean.

PROJECT_STATUS was regenerated this session with the full session-060
delta already applied (TD#87/#88/#94/#95 closed; TD#100 added; BUG-006
added; SC-unit rows already present from the handoff-060 bookkeeping
that was in fact already in the file). Do not re-apply that delta.
See "PROJECT_STATUS state" below.

---

## Session Summary

1. BP-081 -- tage struct reconciliation + TD#87/#88 generation. One
   task, combined at Jeff's direction (handoff-060 had scoped this as
   reconciliation-plus-tie-off; Jeff folded in the real generation).
   Landed green, all in-scope targets this session:
     lint_tage_cntrl / lint_tage / lint_tage_table  0/0
     sim_tage 105/0, sim_tage_fast 105/0
     sim_tage_tasks 0 fail, sim_tage_manual 3/3, sim_tage_table 15/0
     make all exit 0; sim_ittage 211/211 (run separately)
     cov_tage 73.7%, cov_tage_table 79.5%
   Model: claude-opus-4-8 high. Run time ~36m.

   What BP-081 did (7 RTL/tb files):
   - bp_structs_pkg.sv: re-added tage_pred_weak to tage_pred_meta_t;
     confirmed tage_high_conf and tage_provider_ctr absent
     (provider_ctr is an internal signal, not a field); finalized the
     "candidate for removal" comments.
   - tage.sv: retyped the two LIVE FIFOs off the retired cond_pred_*
     wrappers -- uq_data_mem -> tage_upd_inp_t, rb_meta_mem ->
     tage_pred_meta_t -- and collapsed per-subfield writes/reads to
     whole-struct accesses. Behavior-preserving (dropped
     .sc/.sc_valid/.resolved_taken/.cond_mispredict were write-only).
     This is what makes tage elaborate. (TD#94 closed.)
   - tage_cntrl.sv: deleted dead tage_high_conf (write + high_conf_p1
     decl/reset/compute; TD#95 closed); generated the TD#87 one-hot
     decode on the post-mux provider CTR (strong={000,111},
     weak={011,100}, medium=rest); generated TD#88 tage_extd_ctr
     ($signed({2'b00, provider_ctr, 1'b0}) - 5'sd7). Moved the
     update-side UAON gate from the (now-narrowed) strong flag to
     tage_pred_weak -- bit-identical to the old "not-strong == weak"
     behavior; keying on the new strong would wrongly fire UAON on
     medium CTRs.
   - tb_tage.sv: added pred_conf_decode_tst (sweeps all 8 CTR values x
     both slots; checks strong/medium/weak + extd_ctr row-for-row);
     fixed pred_alt_t0_fallback_tst (CTR=101 is now medium); added
     tage_pred_weak=1 to 6 hand-built UAON tests.
   - tb_tage_manual.sv + tb_tage_manual_tasks.svh: removed the dead
     high-conf taps / scoreboard compare (the .svh edit was the
     task's declared exception).
   - tb_tage_tasks.sv: removed a dead high-conf compare that blocked
     sim_tage_tasks compilation. NOT in the task manifest -- IA halted
     and Jeff authorized the out-of-scope edit. (BUG-006; see below.)

2. Doc reconciliation (interactive, not a task). The strong-flag
   redefinition exposed that tage_cntrl_uaon_update_rules.md still
   equated tage_pred_strong with NOT WEAK, which TD#87 broke. Jeff had
   the IA emit an edited copy tage_tmp_uaon_update_rules.md (original
   untouched), inspected it, and folded it into the canonical doc. The
   canonical tage_cntrl_uaon_update_rules.md now gates on
   tage_pred_weak and defines strong as strictly {000,111}. DONE.

3. All-targets audit (interactive). Jeff pushed on whether every
   Makefile target ran. `make all` silently omits sim_ittage,
   sim_tage_manual, and the cov_* targets. IA then ran sim_ittage
   (211/211) and cov_bpu (pulling cov_history/cov_ubtb/cov_loop_pred/
   cov_tage/cov_tage_table) -- all green. This motivated TD#99's CI
   note and is the reason a single "run everything" target is owed.

4. PROJECT_STATUS regenerated with the session-060 delta (see below).

---

## What Was Accomplished

  - tage elaborates and is fully green (BP-081). TD#94/#95 closed.
  - TD#87 (strong/medium/weak decode) and TD#88 (tage_extd_ctr)
    GENERATED in tage_cntrl -- real logic, not tie-off. Closed.
  - tage_pred_weak re-added to tage_pred_meta_t.
  - tb_tage functional coverage for the confidence decode (all 8 CTR
    values, both slots).
  - tage_cntrl_uaon_update_rules.md reconciled to TD#87 (gate on
    tage_pred_weak; strong strictly {000,111}).
  - PROJECT_STATUS.md regenerated with the full session-060 delta.
  - All seven predictor units + bp_history complete and green at unit
    level. bp_cluster top is the next build.

---

## Decisions (session-060)

### BP-081 folded TD#87/#88 into the reconciliation (supersedes tie-off)

handoff-060 scoped BP-081 as reconciliation + tie the ungenerated
SC-facing fields to zero. Jeff folded the real TD#87/#88 generation
into the same task, so the fields are generated, not tied off. The
handoff-060 tie-off policy is historical. Consequence: BP-081 touched
bp_structs_pkg (re-added tage_pred_weak) -- a package edit the tie-off
scope had excluded.

### tage_pred_strong redefined to strictly {000,111}

Previously the field meant NOT WEAK (6 of 8 CTR values). TD#87 makes
it strictly {000,111} (2 of 8), with tage_pred_medium and
tage_pred_weak as the one-hot remainder. This is a semantic change to
an update-consumed signal. The update-side UAON gate was moved to
tage_pred_weak to preserve behavior exactly (verified against
rt_ctr_rows7_8_tst: post-mux CTR=101 must suppress UAON). The
canonical UAON rules doc was reconciled to match.

### provider_ctr stays internal

tage_provider_ctr is an internal convenience signal in tage_cntrl
(equals the post-mux provider CTR), NOT a struct field. Only
tage_extd_ctr is a tage_pred_meta_t field consumed by SC. The struct
field was already absent (commented out); it stays absent.

### tb_tage_tasks.sv edit authorized (out of scope)

The removed tage_high_conf field was referenced in tb_tage_tasks.sv,
which was NOT in the BP-081 manifest and blocked sim_tage_tasks. The
IA halted and requested authorization rather than silently editing
out of scope; Jeff authorized the two-line deletion. Root cause and
corrective rule recorded as BUG-006.

---

## Open Work

### NEXT SESSION -- bp_cluster (BPU) top level + tech-debt burndown

This is the headline task for session-061. All seven predictors and
bp_history are unit-green; the cluster top has not been started.
bp_cluster.md is LOCKED and is the architectural authority. Jeff wants
to build the top and close as much TD as possible.

The cluster-integration prerequisite TDs (these gate a *working*
cluster, several are small and were parked on bp_cluster):
  - #89 / #90  FTB stores branch PC[15:6] (-> sc_upd_inp.branch_range)
    and per-slot backwards-branch sign (-> sc_upd_inp.backwards_branch).
  - #91  bpc routes tage_pred_inp.pc p0->p2 to SC (inp_pc_p2), per slot.
  - #92  bpc captures bp_folded_hist.tage_phr[9:0] -> sc_phr_p2.
  - #84  producer/consumer end-to-end fold check (now also SC ST1-ST3):
    drive a known GHR, take the bp_history fold, hash it in the table,
    confirm the derived index. Needs cluster stimulus.
  - br_imli_mode: parameter; bp_cluster sets SC_BR_IMLI_MODE at the
    sc.sv instantiation if a non-default perf build is wanted.

The cluster-level architectural TBDs that come live when the top is
built (from BP Cluster Open TBDs): G9 (update arbitration), G10
(TAGE/ITTAGE meta overload), G18 (carry field consumer), G19
(NO_BRANCH target), G23 (checkpoint slot reclaim / bp_history HI5),
G24 (FTB flush protocol), G25 (FTB fast-path enable source). Also the
arb layer (#73/#52/#37/#39/#40) and flush (#96) become in-scope once
the top exists.

Scoping note for the task author: bp_cluster is large. Do NOT try to
do the whole top plus all TD in one task. Decompose -- structural top
skeleton first (instantiate the seven predictors + bp_history + arb
stubs, wire the s0-s3 pipeline, get it to elaborate), then the small
wiring TDs (#89-#92), then the behavioral pieces. Build the manifest
file-by-file from the tree, not from this handoff (see BUG-006).

### TD backlog -- closeable without the cluster (Jeff's priority call)

Small/independent items that could be burned down in session-061
alongside or instead of cluster work:
  - #100  tage coverage review: cov_tage 73.7% / cov_tage_table 79.5%
    vs the prior ">90%" claim. Decide genuine under-coverage of the
    new TD#87/#88 logic vs accounting artifact; add directed coverage
    or correct the number. (NEW this session.)
  - #75  sim_ittage_fast target (parallel to sim_tage_fast).
  - #43  ITTAGE CTR 3b->2b.
  - #67/#68  sram_init non-fast path (tage/ittage).
  - #77  scrub prompts / redact absolute paths (RVA_ROOT). Infra.
  - #38  Verilator 5.048 covergroup #7099 re-check.
  - #82  bp_history if/else-if slot cleanup (no behavior change).
  - #83  bp_history decisions.md s6.6 Xiangshan origin sha/date fill.
  - #85  bp_structs_pkg field-sharing review.
  - versions/bp_history.sv retire (stale BP-069 copy; BUG-005).
  - ANTIPATTERNS.md: add the BUG-006 rule (field delete/rename ->
    grep the symbol across the unit, repair the full set; do not
    hand-list). Rule is drafted in BUG-006, wording is Jeff's.

### SC -- remaining unit item (unchanged)

  - verification/sc_coverage_plan.md -- not written.
  - sc_cntrl_ctr_update_rules.md -- optional, write at coverage/tb
    time citing sc_decisions section 10.

### Deferred to cluster / later (unchanged from handoff-060)

  - #69/#70 rollback stimulus -> bp_cluster.
  - #74 broader cluster dual-slot (bp_history part closed BP-072).
  - #1 NUM_PRED_SLOTS=1 reduction (cleanup after cluster).
  - #96 flush behavior definition (needs bpc).
  - #97 shared upstream PQ (decide if implemented).
  - #93 SC efficacy / threshold tuning (PD/perf).
  - #86 8x-weighted TAGE term (PD/perf).
  - #98 SC dual-slot shared scalar state (PD/perf).

---

## PROJECT_STATUS state (regenerated this session)

PROJECT_STATUS.md was regenerated with the full session-060 delta
already in it. Applied:
  - Header -> session 060.
  - Module Status: tage.sv / tage_cntrl.sv / bp_structs_pkg.sv /
    tb_tage_manual.sv / tage_cntrl_uaon_update_rules.md notes updated
    for BP-081; SC (unit) prereq line now "#89-#92 open (#87/#88
    CLOSED BP-081)".
  - TD#87, #88, #94, #95 marked CLOSED BP-081 with decode table,
    extd_ctr formula, and target counts.
  - TD#99 gained the CI motivating evidence (make all blind spot).
  - TD#100 added (tage coverage vs >90% claim).
  - BUG-006 added (manifest-by-inference; tb_tage_tasks.sv omission).
  - Architectural Decisions: TAGE confidence-output generation line
    added; bp_arb_spec TD#94 marked closed.
  - TAGE decomposition section: ">90%" replaced with measured cov
    numbers + TD#100 pointer; #87/#88 moved from deferred to closed.

Note the handoff-060 "bookkeeping not yet applied" list was largely
ALREADY in the file it described (TD#98 present, SC rows present, SC
section already "RTL COMPLETE"); only the genuinely-missing items were
added. Do not re-apply that list.

Provenance caveat: PROJECT_STATUS was rebuilt from pasted text plus
edits, not edited in place on a repo file. The large unchanged tables
were reproduced verbatim, but diff the regenerated file against the
repo copy before committing.

Still-stale doc items (carried, not blockers):
  - sc_decisions.md section-1 [NOT WRITTEN] markers + section-5 FIXME.
  - Header checkboxes on BP-075..081 task files -- set manually as
    Jeff files them.
  - bp_history: s6.6 sha (#83), BP-072/073 status checkboxes,
    versions/bp_history.sv retirement.

---

## Next Session (061)

Jeff is starting this session with FREE CONTEXT by design; session-060
was closed early to keep 061 clean.

At session start Jeff will paste (build the real manifest from the
tree, not from this list):
  PROJECT_STATUS.md
  session_handoff-061.md (this file)
  CLAUDE.md
  planning/arch/bp_cluster.md            (LOCKED authority)
  planning/arch/bp_arb_spec.md           (arb model)
  planning/interfaces/*_interfaces.md    (the seven predictors +
                                          bp_history, as needed)
  and, when the task is scoped, the specific RTL tops to instantiate.

Because PROJECT_CORE methodology is likely in play for a top-level
build (interface currency, dictate-vs-propose, manifest discipline),
consider pasting PROJECT_CORE.md too.

First action: decide the session-061 shape with Jeff -- bp_cluster top
skeleton first (elaborate-only), or a TD burndown pass first, or both.
Then author the first task. Whatever the task, build its Context
Loaded manifest file-by-file from the tree and grep any
deleted/renamed symbol across the unit (BUG-006). Do not implement the
whole cluster in one task; decompose.

---

## Postmortem Record -- PA performance (session-060)

Continuing the trend log (052/053 unchecked claims; 054 over-asking;
055 one under-audited line; 056 late-source/imported framing; 057
unsourced number, volume, manufactured hazards; 058 over-asking; 059
fabricated SV constraint + manifest by inference). 060's dominant
failure was repeating the manifest-by-inference error one turn after
citing it, plus verbosity the user called out twice.

1. Manifest by inference -- again (BUG-006). The BP-081 Context Loaded
   / Deliverables listed the tage testbenches from the BP-080 Phase-1
   reference list ("tb_tage.sv 0 refs, tage_assert* 0 refs") and
   treated that enumeration as complete. It covered only the Phase-1
   manifest. tb_tage_tasks.sv referenced the removed tage_high_conf
   and blocked sim_tage_tasks; Jeff had to authorize the fix manually.
   This is the SAME class as the session-059 postmortem item 2, which
   this PA had cited in the prior turn. A field delete's blast radius
   is a grep result, not a hand-list. The task should have instructed
   the IA to grep the symbol across the unit and repair the full set,
   reporting it -- not carried a fixed file manifest. Corrective rule
   recorded as BUG-006, proposed for ANTIPATTERNS.md.

2. Verbosity. The user twice called out over-long responses ("what the
   fuck is with all the text", "all that fucking bullshit for three
   bullet points"). Several answers to simple questions ran to
   multi-paragraph analyses where three lines would do. Root cause:
   front-loading reasoning the user did not ask for. Carry: answer the
   question asked, at the length it warrants; expand only on request.

3. Pre-litigating the IA's job. On the tb_tage question the PA
   surfaced the strong-redefinition ripple and the update-side
   consumers as things to decide in the task file; the user corrected
   that these are for the IA to derive and repair at read-before-write
   time, and that the decode is TD#87-specified, not a fork. The task
   author's job is the manifest and the spec pointer, not solving the
   RTL in advance.

4. A near-miss caught by checking: the PA claimed tage.sv/tage_cntrl.sv
   were "truncated in the upload." They were not -- the view tool's
   middle-cut display was misread as a truncated file. The user said
   "bullshit check again"; a wc -l / grep of the file boundaries
   showed all 3878 lines present. Verify the artifact before asserting
   a fact about it.

What held:
  - The gated report-first structure (BP-080, prior session) paid off
    again: the retype-not-delete finding meant BP-081's FIFO fix was
    correct on the first IA run.
  - The IA's own work was strong: it correctly derived the UAON gate
    move to tage_pred_weak, proved it against rt_ctr_rows7_8_tst,
    caught the doc inconsistency, and -- when Jeff pushed -- closed
    the all-targets gap (sim_ittage) itself.
  - Reading the real package (not the handoff's summary) caught that
    the handoff's field inventory was stale (provider_ctr already
    removed, medium already present), before it shipped into a task.

Pattern to carry into 061:
  - Build every task manifest from the tree; grep any deleted/renamed
    symbol across the unit before listing files. (The standing rule.)
  - Answer at the length the question warrants. Short questions get
    short answers.
  - The task file carries the manifest and the spec pointer. Let the
    IA derive and repair at read time; do not solve the RTL in the
    task or invent design forks the spec already settles.
  - Verify the artifact (wc/grep) before asserting a fact about a file.

