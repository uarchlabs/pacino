<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-009               |                          |
| Date         | 2026.07.02              |                          |
| Module       | tage, sc                |                          |
| Run time     | 8m.37s                  |                          |
| Ctx %        | 6%                      |                          |
| Model        | claude-opus-4-8[1m] high |                         |
| Resume sha   | a4339d02-9bfe-44f0-8366-b72279fa16f8 |             |
| PA session   | 061                     |                          |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [X] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Planning document audit, group 2 of 3 (tage, sc). Verify the TAGE and
SC planning documents are consistent with the current state of the
associated RTL, packages, testbenches, Makefile, and any library
components actually used. Also verify TAGE-SC cross-references are
consistent, since SC consumes TAGE-generated confidence and extended
counter fields. Read-only sanity check ahead of bp_cluster top level
design. Not a deep dive.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

  Summary

  INFRA-009 is a read-only planning-vs-code drift audit for the TAGE and SC
  group (group 2 of 3), ahead of bp_cluster top-level design. I read all Context
  Loaded docs/RTL/tb/Makefile/lib via three parallel scoped agents, then
  verified the key TAGE-SC cross-references myself against the shipped
  bp_structs_pkg.sv and bp_defines_pkg.sv.

  12 actionable discrepancies written into the Results Capture Summary (only the
  Model header + RESULTS block were modified, per experiment-file rules):

  TAGE (6) — the notable one: tage_pred_strong is still documented as "NOT WEAK"
  in tage_interfaces.md and tage_cntrl_decisions.md, but the shipped struct/RTL
  define it strictly as ctr 000/111 (TD#87). The SC docs already use the new
  meaning, so the TAGE docs disagree with both the struct and the SC side. Plus:
  stale decoration-flags list, wrong T0 index (pc[11:1] vs actual pc[12:2]),
  missing consumer_ready port, wrong T0 init value ("10" vs actual 0), and a
  phantom "rows 18-21" CTR-update path.

  SC (2) — br_imli_mode documented as a runtime port but shipped as a
  compile-time parameter; sc_interfaces.md presents the SC update queue as
  functional when the RTL stubs it (deferred to bp_cluster, TD#73/#94).

  Shared (4) — bp_cluster.md SC table geometry is stale (256/24b/hist{0,4,10,16}
  vs package 512/6b/hist{0,4,16,64}); sram_init.md lists SC as a "future
  consumer" and cites the wrong plusarg (+TAGE_FAST_INIT vs +SC_FAST_INIT); plus
  arb-spec redirect ports with no RTL counterpart, and a tb ST0-coverage
  overstatement.

  Cross-reference (req 5/6) verified positive at the struct level —
  tage_pred_meta_t fields/widths match sc_decisions.md and sc_cntrl.sv
  consumption; the only drift is the stale TAGE-side prose above.

  No errors during execution; nothing required stopping for interaction. Status
  checkboxes in the header were left untouched (outside the permitted edit
  scope) for you to set.


## My Assessment

Files identified as needed clean up:

F1 tage_interfaces.md (316)
F2 tage_cntrl_decisions.md (186)
F3 tage_cntrl_decisions.md (55-56)
F4 tage_interfaces.md (86-ish) line 53 of tage.sv

F5 tage_cntrl_decisions.md (67)
F6 tage_cntrl_decisions.md (224)

F7 sc_table_interfaces.md (232,325)
   sc_interfaces.md ()
   sc_table_hash_rules.md ()
F8 sc_interfaces.md (325)

F9 bp_cluster.md ()
F10 sram_init.md ()

F11 bp_arb_spec.md (3.4)
F12 sc_tb_decisions.md ()

## Claude.ai Assessment

12 findings, all doc-text drift — no RTL bugs, no cross-unit design disagreement once you account for stale prose. Here's how I'd split the fix work:

Tier 1 — factual corrections, ground truth already established this session (no judgment calls):

F1, F2, F3, F4, F5, F6, F9, F10, F12 — each has an unambiguous correct value sitting in bp_defines_pkg.sv / bp_structs_pkg.sv / tage_cntrl.sv / sc.sv already cited in the findings. Mechanical text fixes.

Tier 2 — wording/framing fixes, need care (not deletions):

F8, F11 — these describe real deferred functionality (SC UQ, redirect ports), not fabrications. Fix is "present as deferred to bp_cluster (TD#73/#94)" not "remove."

F1 is the one that actually matters for cluster design — tage_interfaces.md and tage_cntrl_decisions.md still say strong = NOT WEAK, which is the pre-TD#87 definition. If bp_cluster design work reads tage_interfaces.md instead of the struct, it'll get the wrong semantics. I'd prioritize that file even if you stage the rest.

My suggestion: one consolidated editable cleanup task, not nine separate ones. This is a mechanical correction pass against already-known-correct values, not exploratory work — bundling it respects "one experiment = one session" without being wasteful. Scope Context Loaded + Deliverables to exactly the 9 files already listed in your Other Planning File Updates checklist, and give the IA the precise fix per finding (not "go find and fix drift" — that's group-2's job, already done). Each Deliverable line should state old text → new text or the specific correction, sourced to the F-number and RTL/package citation from this Results Capture, so there's no re-interpretation risk on LOCKED/Complete-status docs.

## Follow-on Actions
- [ ] Work with PA coordinate edits.

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
- [ ] bp_arb_spec.md
- [ ] bp_cluster.md
- [ ] sc_interfaces.md
- [ ] sc_table_hash_rules.md
- [ ] sc_table_interfaces.md
- [ ] sc_tb_decisions.md
- [ ] sram_init.md
- [ ] tage_cntrl_decisions.md
- [ ] tage_interfaces.md

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
INFRA-009

## Context Loaded
@planning/arch/tage_cntrl_alloc_rules.md
@planning/arch/tage_cntrl_ctr_update_rules.md
@planning/arch/tage_cntrl_decisions.md
@planning/arch/tage_cntrl_uaon_update_rules.md
@planning/arch/tage_cntrl_use_update_rules.md
@planning/arch/tage_table_entry_formats.md
@planning/arch/tage_table_hash_rules.md
@planning/arch/sc_decisions.md
@planning/arch/sc_table_hash_rules.md
@planning/arch/bp_history_decisions.md
@planning/arch/bp_cluster.md
@planning/arch/bp_arb_spec.md
@planning/arch/sram_init.md
@planning/interfaces/tage_interfaces.md
@planning/interfaces/tage_table_interfaces.md
@planning/interfaces/sc_interfaces.md
@planning/interfaces/sc_table_interfaces.md
@planning/testbenches/manual_tb_decisions.md
@planning/testbenches/tage_mtb_decisions.md
@planning/testbenches/tage_tb_decisions.md
@planning/testbenches/sc_tb_decisions.md
@rtl/core/frontend/bpu/rtl/tage.sv
@rtl/core/frontend/bpu/rtl/tage_cntrl.sv
@rtl/core/frontend/bpu/rtl/tage_table.sv
@rtl/core/frontend/bpu/rtl/tage_bim.sv
@rtl/core/frontend/bpu/rtl/sc.sv
@rtl/core/frontend/bpu/rtl/sc_cntrl.sv
@rtl/core/frontend/bpu/rtl/sc_table.sv
@rtl/core/frontend/bpu/rtl/sc_brimli.sv
@rtl/core/frontend/bpu/rtl/bp_history.sv
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/core/frontend/bpu/tb/tb_tage.sv
@rtl/core/frontend/bpu/tb/tb_tage_table.sv
@rtl/core/frontend/bpu/tb/tb_tage_manual.sv
@rtl/core/frontend/bpu/tb/tb_tage_manual_tasks.svh
@rtl/core/frontend/bpu/tb/tb_tage_tasks.sv
@rtl/core/frontend/bpu/tb/tage_assert.sv
@rtl/core/frontend/bpu/tb/tage_assert_bind.sv
@rtl/core/frontend/bpu/tb/tb_sc.sv
@rtl/core/frontend/bpu/tb/tb_sc_cntrl.sv
@rtl/core/frontend/bpu/tb/tb_sc_table.sv
@rtl/core/frontend/bpu/tb/tb_sc_brimli.sv
@rtl/core/frontend/bpu/tb/tb_bp_pkg.sv
@rtl/core/frontend/bpu/Makefile
@rtl/lib/rtl/bw_ram.sv
@rtl/lib/rtl/dual_lm1.sv
@rtl/lib/rtl/sat_alu.sv
@rtl/lib/rtl/sram_init.sv

## Hypothesis

The TAGE and SC planning documents are believed current after
session-060 (BP-081: TD#87/#88 generated in tage_cntrl, closed) and
session-058/059 (SC unit complete, sc_decisions.md draft). This task
tests that belief against the actual shipped RTL/tb/build files, and
additionally tests that the SC-side documentation of TAGE-consumed
fields (tage_pred_strong/medium/weak, tage_extd_ctr) matches what
TAGE actually generates post-BP-081.

## Background

TAGE and SC are grouped together because SC directly consumes
TAGE-generated signals: sc_decisions.md section 8 defines the SC sum
equation using tage_extd_ctr and tage_pred_medium (TD#87/#88, closed
BP-081, session-060). bp_arb_spec.md defines a standalone-SC
arbitration model (separate SC update queue, TAGE response buffer
serving as SC's prediction queue) that both units' RTL must agree
with. This audit precedes bp_cluster top level design, which will
treat these planning documents as the interface authority for
instantiating TAGE and SC in the cluster.

Unlike the group 1 (ftb) audit, shared documents (bp_cluster.md,
bp_arb_spec.md, bp_history_decisions.md, manual_tb_decisions.md) are
NOT to be skipped even if their TAGE/SC content appears to be already
tracked by open technical debt items. Open the documents and read the
TAGE/SC-relevant sections in full.

## Binding Previous Decisions

None. This is a read-only audit; no design decisions are made or
overridden.

## Specific Requirements

1. Read every planning document listed in Context Loaded. For the
   shared documents (bp_cluster.md, bp_arb_spec.md,
   bp_history_decisions.md, manual_tb_decisions.md, sram_init.md),
   read the TAGE- and SC-relevant sections in full -- do not skip a
   shared document on the basis that its content is already tracked
   by an open TD. If a section is genuinely irrelevant to TAGE/SC
   (e.g. an FTB- or RAS-only section), note that it was scoped out
   and why.
2. Read the associated RTL, package (TAGE/SC-relevant portions only),
   testbenches, and Makefile (TAGE/SC targets only) files.
3. For each lib component listed, first confirm TAGE or SC actually
   instantiates it before reviewing it. Skip any that neither uses.
4. Compare planning document claims (port lists, parameter names and
   values, field definitions, behavioral rules, module structure)
   against what the RTL/tb/Makefile actually contain, for TAGE and
   SC independently.
5. Specifically verify the TAGE-SC cross-reference: confirm
   sc_decisions.md's description of tage_pred_strong/medium/weak and
   tage_extd_ctr (the sum equation in section 8, the chooser in the
   two-corner section, and any related text) matches what
   tage_cntrl.sv and bp_structs_pkg.sv actually generate post-BP-081.
   Confirm bp_structs_pkg.sv field names/widths for tage_pred_meta_t
   agree with both tage_cntrl_decisions.md and sc_decisions.md.
6. Verify bp_arb_spec.md's standalone-SC arbitration model (separate
   SC UQ, TAGE response buffer as SC PQ, CSR sc_enable) is consistent
   with the arb-related ports/stubs actually present in sc.sv and
   tage.sv.
7. Report only actionable discrepancies: something a planning doc
   states that the code does not do, or vice versa, or a TAGE-side
   and SC-side document that disagree with each other, that would
   mislead someone using these docs as the interface/behavior
   authority.
8. Do not report items that require no action, and do not report
   items already flagged or resolved elsewhere in the documents
   themselves (e.g. an open TD already tracking the gap).

## Constraints

- Read-only. Do not modify, create, or delete any file.
- This is a light sanity check, not a deep-dive audit. Do not
  exhaustively re-derive every signal; check for drift between doc
  claims and code reality, and between the TAGE-side and SC-side
  documents where they describe the same interface.
- Keep the report brief. Bullet points, not prose paragraphs. If
  nothing is found, write "No issues found."
- Do not read or write any file not listed in Context Loaded or
  Deliverables.
- Ctx % in the Task Header is captured manually by Jeff. Do not
  populate it.

## Deliverables

Write findings into the Results Capture Summary section only, per
Constraints above. Most other Results Capture sections do not apply
to this task type -- mark them N/A rather than leaving them blank.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================
```
## Summary
Group 2 (tage, sc) planning-vs-code audit. Read all Context Loaded
docs, RTL, tbs, Makefile, and lib. Findings below (actionable drift
only). Cross-reference req 5/6 verified positive at the struct level;
the only drift there is stale TAGE-side prose (F1/F2).

TAGE:
- F1: tage_pred_strong defined as "NOT WEAK" in
  tage_interfaces.md (line 316) and tage_cntrl_decisions.md
  (line 186, "ctr !=3 and !=4"). Stale pre-TD#87. Shipped
  tage_pred_meta_t (bp_structs_pkg.sv:194-197) and tage_cntrl.sv
  define strong = ctr 000 or 111 ONLY. sc_decisions.md and
  tage_cntrl_uaon_update_rules.md already use the new meaning, so
  these two TAGE docs disagree with both the struct and the SC doc.
- F2: tage_cntrl_decisions.md "Decoration flags" list (line 186 ff)
  omits tage_pred_medium and tage_extd_ctr, both now populated in
  the struct/RTL (TD#87/#88).
- F3: tage_cntrl_decisions.md (lines 55-56) says T0 RAM index =
  pc[11:1]. Actual index is pc[12:2] (tage_bim.sv, and correctly
  documented in tage_table_hash_rules.md and
  tage_table_interfaces.md). decisions.md is wrong.
- F4: tage_interfaces.md port list omits the consumer_ready input
  present on tage.sv (line 53).
- F5: tage_cntrl_decisions.md (line 67) "T0 initializes to 10".
  TAGE_SRAM_INIT_VALUE = 0 (bp_defines_pkg.sv:212), so T0 comes up
  00 (strongly not-taken), not 10.
- F6: tage_cntrl_decisions.md CTR-update summary (lines 224-226)
  cites "rows 18-21" for prm_comp==0 & alt_comp>0. Authoritative
  tage_cntrl_ctr_update_rules.md has only row 18, marked
  ASSERT/invalid (case is architecturally impossible; RTL scan
  cannot produce it). Summary describes a nonexistent update path.

SC:
- F7: br_imli_mode documented as a runtime input port on sc_brimli
  (sc_table_interfaces.md port list line 232, semantics 325-327;
  sc_table_hash_rules.md lines 136-138). RTL made it a compile-time
  parameter BR_IMLI_MODE (sc_brimli.sv:60, from sc.sv
  SC_BR_IMLI_MODE) per sc_decisions.md section 12 / session-059.
  Interface + hash docs (LOCKED 2026-06-30) predate the change.
- F8: sc_interfaces.md "Arbitration Model" states as fact that SC
  has a functional separate update queue (entry sc_upd_inp_t,
  sc_uq_not_full asserted when room). sc.sv stubs
  sc_uq_not_full=1'b1 and sc_upd_rdy=all-ones with the UQ/credit
  arbiter deferred to bp_cluster (TD#73/#94). Doc does not mark
  these ports as stubbed/deferred.

Shared:
- F9: bp_cluster.md SC geometry stale. It lists ST0-ST3 as 256
  entries / 24b wide / hist {0,4,10,16} (lines 100-104, repeated in
  the Folded Histories block 313-315). Package
  (bp_defines_pkg.sv:242-246) is 512 entries, 6b counter,
  hist {0,4,16,64}, ST4=1024. bp_history_decisions.md and
  sc_tb_decisions.md carry the correct values; error is isolated to
  bp_cluster.md.
- F10: sram_init.md stale on SC. (a) Lists sc.sv/sc_table.sv as
  "future consumers"; sc.sv now instantiates sram_init
  (u_sram_init). (b) Plusarg table says SC uses +TAGE_FAST_INIT;
  actual plusarg is +SC_FAST_INIT (sc_table.sv, sc.sv, sc_brimli.sv;
  Makefile sim_sc_fast).

Minor / lower priority:
- F11: bp_arb_spec.md section 3.4 redirect ports
  (tage_redir_val_p2, sc_redir_val_p3) have no counterpart on
  tage.sv/sc.sv. Plausibly deferred cluster work; related to F8.
  Rest of the standalone-SC arb model matches RTL: sc_enable CSR
  input present (stubbed, IC-SC-05) and the TAGE response buffer
  appears as the tage_pred_meta_p2/tage_pred_rdy_p2 inputs on sc.sv.
- F12: sc_tb_decisions.md implies ST0 coverage ("a separate
  instance or a parameter override"); tb_sc_table.sv instantiates
  only ST1 (P_THIS_TABLE=1). No ST0 instance exists.

Verified consistent (no action): TAGE-SC cross-reference (req 5) --
tage_pred_meta_t strong/medium/weak/extd_ctr fields and widths match
sc_decisions.md sections 8-9 and sc_cntrl.sv consumption (extd_ctr
sign-extended at weight 1 per TD#86, strong->tage_hi, medium->
tage_med). SC sum equation, two-corner chooser, update/threshold
adaptation, index and BrIMLI hashes, top-level SC port list, TAGE
tagged-entry format, index/tag/u_eff/USE/UAON rules, and the manual
and directed tb structure all match their docs.

Lib scope (req 3): sram_init.sv and bw_ram.sv are instantiated by
TAGE/SC (reviewed). dual_lm1.sv and sat_alu.sv are not instantiated
by TAGE or SC -- scoped out.

## Test Matrix (testbench sessions only, omit otherwise)
N/A

## What was delivered
Read-only audit findings (Summary section above). No RTL/tb changes.

## Test Case Results
N/A (read-only audit; no suites run per Constraints).

## Assumptions made not explicit in the prompt
- F5 assumes T0 fast/sram init drives TAGE_SRAM_INIT_VALUE (=0)
  into T0; confirmed via bp_defines_pkg.sv:212 and tage.sv init path.
- "TAGE/SC-relevant sections" of shared docs interpreted as the SC
  table geometry, sram_init, arbitration, and history-fold entries;
  FTB/RAS/ITTAGE-only sections were read past, not audited.

## Decisions made not explicit in the prompt
N/A

## RVA23 compliance risks and gaps noticed
None. Findings are documentation drift, not architecture/ISA gaps.

## Deferred Work
- F8/F11 (SC update queue + redirect ports) are genuine deferrals to
  bp_cluster (TD#73/#94), not doc-only errors; the drift is that
  sc_interfaces.md / bp_arb_spec.md present them as present rather
  than deferred. Fixing the doc wording is a follow-on.

## Other Notes
- Cosmetic-only, not counted as findings: tage_interfaces.md lines
  290/305 retain ITTAGE copy-paste names (ittage_upd_rdy_u1 /
  ittage_upd_val_u0).

## Files Modified
None (read-only task; only this file's Model header + Results
Capture written, per CLAUDE.md experiment-file rules).

# Context Usage Report

Model: claude-opus-4-8[1m] (Opus 4.8, 1M context)
Total: 58.7k / 1,000,000 tokens (6%)
Free space: 940.6k (94.1%)

## Usage by category

| Category      | Tokens | Percent |
|---------------|--------|---------|
| System prompt | 2.8k   | 0.3%    |
| System tools  | 16k    | 1.6%    |
| MCP tools     | 1.5k   | 0.1%    |
| Memory files  | 3.8k   | 0.4%    |
| Skills        | 2k     | 0.2%    |
| Messages      | 34.8k  | 3.5%    |
| Free space    | 940.6k | 94.1%   |

## Notes

- The 58.7k reflects only the main-thread context. The three audit
  sub-agents read the ~50 files in their own isolated context
  windows (~350k tokens combined) and returned compact findings,
  so the full audit landed here as only 34.8k of messages.
- Memory files: CLAUDE.md 3.6k, MEMORY.md 196 tokens.

:: RESULTS:END ::

