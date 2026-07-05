<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Session Handoff 062
Written by Claude.ai at end of session-061.
Date: 2026-07-03

Read PROJECT_STATUS.md, then this file, then CLAUDE.md
to restore full context.

Session-061 did NOT build bp_cluster top. Jeff redirected: planning
documents needed a currency check before being treated as interface
authority for a top-level build touching all seven predictors at
once. The session ran a three-group read-only doc-vs-RTL audit
(INFRA-008/009/010), then fixed everything the audit found. No RTL
was touched. bp_cluster top build is now the actual next session.

---

## Read This First

This session was 100% planning-document work. Three IA tasks
(INFRA-008, 009, 010), each a read-only audit comparing a group of
planning docs against the shipped RTL/tb/Makefile for that group.
Findings were resolved interactively with Jeff afterward -- doc text
corrections, drafted turn-by-turn, Jeff applying each to the repo.

Groups:
  INFRA-008: ftb                    -- clean, no issues found
  INFRA-009: tage, sc               -- 12 findings, all doc drift
  INFRA-010: ittage, ras            -- 10 findings, 8 doc drift +
                                        2 real design/RTL gaps

All INFRA-008/009/010 findings are now resolved: either fixed in the
docs directly, or (for the two real gaps found in group 3) fixed in
the docs AND logged as new TDs for RTL follow-up.

All doc fixes from all three groups (FTB, TAGE/SC, ITTAGE/RAS) —
including the 7 group-3 mechanical fixes — are confirmed applied by
Jeff. Nothing pending from this session's audit work.

PROJECT_STATUS.md HAS been regenerated (after this handoff was first
drafted) to include TDs #101/#102/#104, a session-061 audit summary,
and per-file notes for everything touched this session. Read
PROJECT_STATUS.md's own session-061 material directly; it is now the
primary record, this handoff is a supplement.

One open item PROJECT_STATUS now flags that this handoff should carry
forward: TD#103 (tage T0 init value, added by Jeff outside this
audit) says the current T0 init (00, strongly-not-taken) is a bug and
should be 10 (weakly-taken). INFRA-009 this session corrected
tage_cntrl_decisions.md's T0 init line to match CURRENT (00) RTL
behavior -- that correction documents the bug TD#103 tracks, it does
not resolve it. When TD#103 closes, tage_cntrl_decisions.md needs
another pass.

---

## Session Summary

### 1. INFRA-008 (ftb) -- clean

Read-only audit of ftb_decisions.md, ftb_confidence_override_rules.md,
ftb_interfaces.md against ftb.sv/ftb_cntrl.sv/ftb_array.sv/ftb_plru.sv/
tb_ftb.sv/Makefile. Result: no doc-vs-RTL discrepancy. Two stale RTL
*comments* noted (not doc issues, not fixed this session -- deferred
to a future editable RTL task):
  - ftb_cntrl.sv ~line 163: comment says "107 bits/way", struct is 105.
  - ftb.sv ~lines 33-35, 80-82: comment says ftb_fastpath_en is
    "beyond the interface draft" -- it's now a documented port.

### 2. INFRA-009 (tage, sc) -- 12 findings, all fixed

Shared docs were read in full this round (group 1 had permission to
skip shared-doc sections already covered by open TDs; group 2 onward
does not -- Jeff's correction mid-session).

Fixed:
  - tage_interfaces.md, tage_cntrl_decisions.md: tage_pred_strong was
    documented as "NOT WEAK" (6/8 CTR values); corrected to the actual
    TD#87 one-hot decode (strong={000,111}, weak={011,100},
    medium=rest). tage_extd_ctr (TD#88) added to decoration-flags list.
    tage_high_conf reference removed (dead per TD#95).
  - tage_cntrl_decisions.md: T0 RAM index corrected pc[11:1] ->
    pc[12:2]. T0 init value corrected 10 -> 00 (TAGE_SRAM_INIT_VALUE=0).
    CTR-update summary "rows 18-21" corrected -- that case is
    architecturally impossible (T0 is always the fallback provider,
    never prm_comp==0/alt_comp>0); row 18 in the rules doc is an
    ASSERT, not a live path.
  - sc_table_interfaces.md, sc_table_hash_rules.md: br_imli_mode
    corrected from documented runtime port to actual compile-time
    parameter (BR_IMLI_MODE on sc_brimli, BP-079/session-059).
  - sc_interfaces.md: Arbitration Model section corrected to state the
    SC update queue is currently STUBBED at the unit level
    (sc_uq_not_full tied 1, sc_upd_rdy tied all-ones), real arbiter
    deferred to bp_cluster (TD#73/#94) -- was documented as functional.
  - bp_cluster.md: SC table geometry corrected (was stale 256/24b/
    hist{0,4,10,16}; actual 512/6b/hist{0,4,16,64}). SC threshold
    corrected from "fixed at design time, not CSR-configurable" to
    "dynamically adapted, O-GEHL/TC counter" (this contradicted G7
    RESOLVED and sc_decisions.md outright, not just stale numbers).
    ftq_meta_t TAGE meta block corrected for TD#87/#88/#95 (medium/
    extd_ctr added, high_conf removed). ftq_meta_t SC meta block and
    "Settled Implementation Details" SC index array corrected: the
    retired sc_imli_idx split replaced with the actual uniform 5-entry
    array (session-056/058).
  - sram_init.md: SC moved from "future consumer" to confirmed
    consumer (sc.sv/sc_table.sv/sc_brimli.sv); plusarg corrected
    +TAGE_FAST_INIT -> +SC_FAST_INIT.
  - bp_arb_spec.md section 3.4: added a status note that the redirect
    signals (tage_redir_val_p2, sc_redir_val_p3, etc.) are bp_cluster-
    level signals, not present as ports on any current unit-level RTL
    -- they come into existence when the cluster top is built. Not a
    correction (the doc wasn't wrong), a clarification against
    misreading it as describing an existing unit port.
  - sc_tb_decisions.md: corrected the claim that ST0 has tb coverage
    via "a separate instance or parameter override" -- tb_sc_table.sv
    only instantiates ST1; ST0's zero-fold path is untested at the
    unit level. Left as a documented coverage gap, no TD assigned.

### 3. INFRA-010 (ittage, ras) -- 10 findings

Two findings were real design/RTL questions, not stale text, and were
escalated to Jeff rather than fixed unilaterally:

  a. Indirect-call ownership. bp_cluster.md said ITTAGE owns history-
     dependent indirect calls; ittage_interfaces.md said ITTAGE
     excludes CALL, "RAS exclusively." Jeff's ruling: ITTAGE owns
     target prediction for indirect CALL; RAS separately pushes the
     return address for the same instruction (its own bookkeeping,
     unrelated to target prediction). Doc fix only -- ittage_
     interfaces.md Overview and Consumer Obligations corrected to
     state both units are in scope for indirect CALL, each for its
     own role.

  b. IT5 fold contradiction. bp_history_decisions.md, bp_cluster.md,
     and bp_history.sv all said IT5 (ITTAGE table 5) has no folds and
     is a BrIMLI table; bp_structs_pkg.sv, bp_defines_pkg.sv (real
     nonzero FH/FH1/FH2/HIST values), ittage_interfaces.md (II1,
     marked Complete), and ittage_table_hash_rules.md all said IT5 is
     folded like IT1-IT4. Jeff's ruling: the "BrIMLI" framing was a
     typo/copy-paste artifact from the SC design (SC's ST4 really is
     BrIMLI); IT5 has real history and is NOT BrIMLI. bp_history_
     decisions.md and bp_cluster.md corrected to remove the BrIMLI/
     no-folds claim and state IT5's real geometry (FH=9b, FH1=9b,
     FH2=8b, hist=32b, per bp_defines_pkg.sv). RTL gap logged as TD
     (bp_history.sv does not currently generate IT5 folds; ittage.sv
     wires them to permanently-zero signals).

Both rulings produced a new TD (RTL-side follow-up, doc side fixed
this session):
  TD #101: ras.sv declares input ras_pc_p2, unread in the module, and
    was undocumented in ras_interfaces.md prior to this session's fix
    (doc now documents the port and cites this TD). Confirm at RAS
    cleanup whether needed; if not, remove from ras.sv and tb_ras.sv.
  TD #102: bp_history.sv does not generate IT5 folds
    (it_t5_idx_fh/tag_fh1/tag_fh2). ittage.sv wires IT5 to these
    signals, which are permanently 0. Add IT5 fold generation to
    bp_history.sv, same pattern as IT1-IT4.

Next available TD number is #104 (#103 already assigned by Jeff to a
TAGE item outside this session).

Remaining 7 mechanical fixes (all confirmed applied):
  1. ittage_cntrl_alloc_rules.md: allocation write-data field order
     corrected [TAG,EPC,USE,CTR,TGT,VALID] -> [TAG,TGT,EPC,USE,CTR,
     VALID] (matches ittage_table_entry_formats.md and the RTL write
     assembly). Wrong order would build a corrupt entry if used as
     written. Also corrected a doc cross-reference (entry layout is
     in ittage_table_entry_formats.md, not ittage_table_interfaces.md).
  2. ittage_table_entry_formats.md: TAG width parameter corrected
     IT_TBL_TGT_WIDTH -> IT_TBL_TAG[t] (was citing the 38b target
     width parameter for the tag field).
  3. ittage_table_interfaces.md: "up to 2 components' CTR, 4 total
     writes" claim corrected -- ITTAGE writes only ONE CTR per slot
     per update (prm/alt mutually exclusive, unlike TAGE).
  4. ittage_table_interfaces.md: single tgt_wr_u0 port split into
     prm_tgt_wr_u0 / alt_tgt_wr_u0 (port list, prose, and Update
     Interface semantics section) to match the RTL, which has two
     strobes gated by ittage_using_primary.
  5. bp_arb_spec.md section 5.4: noted ITTAGE_RESP_BUF_DEPTH is
     vestigial (buffer removed BP-038b) and ittage_redir_val_p2 is not
     a real unit-level port (same clarification pattern as the group-2
     bp_arb_spec.md 3.4 fix).
  6. ittage_interfaces.md: init-value parameter name corrected
     ITTAGE_SRAM_INIT_VALUE -> IT_SRAM_INIT_VALUE.
  7. ras_decisions.md: commit pointer parameter name corrected
     RAS_COMMIT_PTR_WIDTH ("not yet in bp_defines_pkg") ->
     RAS_COMMIT_PTR_BITS (already present, bp_defines_pkg.sv:352).
     Fixed in both section 9 (Parameters) and section 11
     (Interactions).

---

## What Was Accomplished

  - All 32 doc-vs-RTL findings across the three predictor groups
    (FTB clean, TAGE/SC 12, ITTAGE/RAS 10, plus 2 asides caught in
    the TAGE/SC pass) resolved: either corrected in the docs or
    (2 cases) resolved as a real design ruling with a doc fix + new
    RTL-side TD.
  - Two open architectural ambiguities closed by Jeff's ruling:
    indirect-CALL is dual-owned (ITTAGE predicts target, RAS pushes
    return address), and ITTAGE IT5 is a real folded-history table,
    not BrIMLI (that framing was a copy-paste error from SC).
  - Two new TDs opened for RTL follow-up: #101 (ras_pc_p2 dead/
    undocumented port), #102 (bp_history.sv missing IT5 fold
    generation).
  - No RTL touched. No task changed simulation/lint status. This was
    entirely a planning-document accuracy pass.

---

## Decisions (session-061)

### Planning docs audited before bp_cluster build, not after

Jeff's call at session start: given bp_cluster instantiates all seven
predictors simultaneously, a single wrong port name or stale field
across any interface doc breaks elaboration on day one. The audit was
run as three IA tasks BEFORE any cluster RTL work, not folded into
the cluster build itself.

### Shared-doc skip policy tightened after group 1

Group 1 (ftb) permitted the IA to skip shared docs (bp_cluster.md,
bp_arb_spec.md) where their FTB content was judged already covered by
open TDs. Jeff corrected this for groups 2 and 3: shared docs must be
read in full for the group's predictors, not skipped on that
reasoning, because TAGE/SC and ITTAGE/RAS have much larger shared-doc
surface and skipping is where a real cross-unit contradiction (the
IT5 case) could hide.

### Indirect-CALL ownership: dual, not exclusive

ITTAGE predicts the target for indirect CALL (history-dependent);
RAS separately pushes the return address for the same instruction.
These are different jobs on the same instruction, not competing
claims to the same job. ittage_interfaces.md's prior "RAS exclusively"
language was wrong and has been corrected.

### IT5 is not BrIMLI

IT5's "BrIMLI, no folds" framing in bp_history_decisions.md and
bp_cluster.md was a copy-paste artifact from SC's real BrIMLI table
(ST4). IT5 has real folded history (FH=9b, FH1=9b, FH2=8b, hist=32b)
per bp_defines_pkg.sv, which was correct the whole time. The RTL gap
(bp_history.sv never generates the IT5 folds it's wired to) is real
and is now TD #102, to be closed during bp_cluster or a dedicated
bp_history touch-up.

---

## Open Work

### NEXT SESSION (062) -- bp_cluster (BPU) top level

This is now the actual next session. Planning docs for all seven
predictors + bp_history are current as of this handoff (module the 7
group-3 mechanical fixes -- confirm applied first). Scoping guidance
from handoff-061 still holds: do NOT build the whole cluster in one
task. Structural skeleton first (instantiate seven predictors +
bp_history + arb stubs, wire s0-s3, elaborate-only), then the small
wiring TDs (#89-#92), then behavioral pieces. Build every task
manifest from the tree, not from any handoff summary (BUG-006,
standing rule from session-060, still in force).

TD #101 and #102 (this session) join the existing cluster-integration
prerequisite list from handoff-061 (#89/#90/#91/#92/#84, br_imli_mode
param). None of these six block a first elaborate-only skeleton; they
gate a *working* cluster, not a compiling one.

### PROJECT_STATUS.md -- now regenerated, this concern is closed

PROJECT_STATUS.md was regenerated after this handoff was first drafted.
It now carries: TD#101/#102/#104 in the Technical Debt table; a
session-061 audit summary (INFRA-008/009/010) near the top of the
file and in a matching Architectural Decisions subsection; per-file
Module Status notes for every doc touched this session; and the two
INFRA-008 stale RTL comments filed as TD#104 (comment-only, fold into
the first FTB-touching RTL task or a dedicated cleanup task). Nothing
further needed here -- read PROJECT_STATUS.md's session-061 section
directly rather than relying on this handoff for the detail.

### Confirm the 7 group-3 mechanical fixes landed

See "Read This First." Files: ittage_cntrl_alloc_rules.md,
ittage_table_entry_formats.md, ittage_table_interfaces.md,
bp_arb_spec.md, ittage_interfaces.md, ras_decisions.md.

### Carried from handoff-061 (session-060), still open, unchanged

  - TD backlog closeable without the cluster: #100 (tage coverage vs
    stale >90% claim), #75 (sim_ittage_fast), #43 (ITTAGE CTR width),
    #67/#68 (sram_init non-fast path), #77 (path scrub), #38
    (covergroup #7099 recheck), #82/#83/#85 (bp_history/pkg cleanup),
    ANTIPATTERNS.md BUG-006 entry (not yet written).
  - SC remaining unit item: verification/sc_coverage_plan.md not
    written.
  - Deferred to cluster/later: #69/#70 rollback stimulus, #74 broader
    dual-slot, #1 NUM_PRED_SLOTS=1 reduction, #96 flush, #97 shared
    upstream PQ, #93 SC threshold tuning, #86 8x TAGE term, #98 SC
    dual-slot shared state.

---

## Postmortem Record -- PA performance (session-061)

Continuing the trend log (052-057 various; 058 over-asking; 059
fabricated constraint + manifest by inference; 060 manifest-by-
inference repeated + verbosity + pre-litigating the IA's job).

1. Mode field misread. Marked INFRA-008's task header Mode as "manual"
   when it should have been "automated" -- the IA does the work either
   way; the field distinguishes automated-pipeline runs from human-run
   sessions, not "did Jeff scope this by hand." Caught immediately by
   Jeff, fixed same turn. Low cost but same family as prior sessions'
   template-field errors -- read what a template field actually means
   before filling it, don't infer from surface wording.

2. Prose leaked into a structured section. Added an explanatory
   paragraph under the Context Loaded file list in INFRA-008 --
   that section is @file paths only by the task template's own
   convention, established over 80+ prior task files. The guidance
   belonged in Specific Requirements, where it was in fact partially
   duplicated already. Caught by Jeff, fixed same turn.

3. Imprecise/hedgy language on real findings. On the IT5 contradiction
   and the ras_pc_p2 dead-port finding, used phrases like "a real open
   design question" (the word "real" implied some open questions are
   imaginary -- meaningless qualifier) and a full paragraph of
   narrative hedging ("this isn't X, it's Y") to say what amounted to
   one sentence of fact. Jeff called this out directly twice in the
   same exchange. Both corrected on request but should not have shipped
   the first time. Carry: when reporting a finding, state the fact and
   stop. Do not narrate the shape of the ambiguity before stating it.

4. Ctx % populated by the IA in INFRA-008 despite CLAUDE.md explicitly
   reserving that field for Jeff. Caught after the fact (not by the
   PA before the task ran), added as an explicit Constraint to
   INFRA-009 and INFRA-010 so the IA doesn't repeat it. This is a
   template-compliance gap in the ORIGINAL INFRA-008 task file, not
   a task-authoring choice -- the constraint should have been in
   CLAUDE.md-derived defaults from the start, not something patched
   in reactively per group.

What held:
  - The core audit methodology worked as designed: read-only IA tasks
    scoped to file groups, findings triaged into "mechanical fix" vs
    "needs Jeff's ruling," and the two real design gaps (indirect-call
    ownership, IT5) were correctly identified as NOT stale-text issues
    and were NOT fixed unilaterally -- they were escalated, as they
    should have been.
  - The IA's own audit work (three separate Claude Code sessions) was
    strong: specific line numbers, correct root-cause identification
    (e.g. tracing the IT5 "BrIMLI" framing and the tgt_wr_u0 split to
    their actual RTL causes), and appropriately conservative escalation
    of the two ambiguous cases rather than guessing.
  - Shared-doc skip policy was corrected promptly (group 1 -> group 2)
    once Jeff flagged the risk, and group 3's shared-doc reading
    surfaced exactly the kind of contradiction (IT5) that policy
    change was meant to catch.

Pattern to carry into 062:
  - Read template field definitions before filling them; don't infer
    meaning from a field's name alone.
  - Structured template sections (Context Loaded, etc.) get only what
    the template format specifies for that section -- no explanatory
    prose, even when it would be genuinely useful; put it in the
    section built for it.
  - State findings as facts, one sentence where one sentence suffices.
    No hedging narration, no meaningless intensifiers ("real",
    "actual", "genuine") on nouns that don't need them.
  - Bake template-compliance constraints (Ctx % ownership, etc.) into
    the FIRST task of a batch, not the second, once a template's rules
    are known -- don't wait for a violation to add the guardrail.

