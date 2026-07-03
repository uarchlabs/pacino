<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-010               |                          |
| Date         | 2026.07.02              |                          |
| Module       | ittage, ras             |                          |
| Run time     | 8m.23s                  |                          |
| Ctx %        | 6%                      |                          |
| Model        | claude-opus-4-8[1m] normal |                        |
| Resume sha   | e2fa1db1-ccba-473a-95de-7bea5c4fd74d |             |
| PA session   | 061                     |                          |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [X] cleanup     [ ] testbench       [ ] verification
Mode:   [X] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Planning document audit, group 3 of 3 (ittage, ras). Verify the
ITTAGE and RAS planning documents are consistent with the current
state of the associated RTL, packages, testbenches, Makefile, and
any library components actually used. Also verify the ITTAGE/RAS/FTB
three-way JALR role split is consistently described across their
respective documents. Read-only sanity check ahead of bp_cluster top
level design. Not a deep dive.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

  INFRA-010 complete — ITTAGE/RAS planning-doc audit (group 3 of 3)

  Read-only audit. All 42 Context Loaded files read and cross-checked via four
  parallel focused agents (ITTAGE, RAS, JALR-split/folds/shared-docs,
  Makefile+lib). Findings written into the Results Capture Summary; Model header
  populated. No files changed except prompts/INFRA-010.md (the required results
  file).

  Actionable discrepancies found:

  ITTAGE (doc vs RTL):
  - alloc_rules.md:76 alloc write-data field order wrong
  ([TAG,EPC,USE,CTR,TGT,VALID] vs actual TAG,TGT,EPC,USE,CTR,VALID) — would
  build a corrupt entry.
  - ittage_table_entry_formats.md:57 names IT_TBL_TGT_WIDTH for TAG width;
  should be IT_TBL_TAG[t].
  - Interface docs describe one tgt_wr_u0 strobe; RTL split it into
  prm_tgt_wr_u0/alt_tgt_wr_u0.
  - ittage_table_interfaces.md:35-38 "2 components' CTR / 4 writes" contradicts
  RTL (provider-only, prm XOR alt) and the same doc's :257-260.
  - bp_arb_spec.md §5.4: ITTAGE_RESP_BUF_DEPTH vestigial (buffer removed
  BP-038b); ittage_redir_val_p2 isn't a port.
  - ittage_interfaces.md:279 ITTAGE_SRAM_INIT_VALUE vs actual
  IT_SRAM_INIT_VALUE.

  RAS (doc vs RTL):
  - ras.sv:44 ras_pc_p2 absent from the LOCKED port list (ras_interfaces.md §4);
  also declared-but-unread in RTL.
  - ras_decisions.md:448-450 names RAS_COMMIT_PTR_WIDTH "not yet in
  bp_defines_pkg"; actual RAS_COMMIT_PTR_BITS is at bp_defines_pkg.sv:352.

  Cross-doc / JALR split (req 5):
  - Indirect-CALL ownership disagreement: bp_cluster.md routes history-dependent
  indirect calls to ITTAGE (it_indirect_call meta), but ittage_interfaces.md
  gates INDIRECT_CALL out of ITTAGE ("RAS exclusively"). Target predictor for
  that case is ambiguous. Not in any TD.

  Folds (req 6):
  - IT5 fold contradiction: authority (bp_history_decisions.md, bp_cluster.md) +
  bp_history.sv say IT5 (BrIMLI) has no folds and never drive it_t5_*; but the
  structs/params/ittage_interfaces.md (II1 marked Complete)/hash_rules.md treat
  IT5 as folded. ittage.sv:511-513 wires IT5 to folds that are permanently 0.
  Live doc-vs-code + doc-vs-doc conflict, not tracked.

  Clean: Makefile ITTAGE/RAS targets and used lib components (bw_ram,
  sram_init); dual_lm1/sat_alu correctly unused. Minor/no-action items
  (sram_init.md omitting RAS, 7.2 p0 wording) recorded under Other Notes.

  Per the file's write-scope rules, I left the Status: checkbox untouched (it
  lives outside the RESULTS markers). You'll likely want to mark it complete
  manually, along with Run time / Ctx %.


## My Assessment

Issues not numbered by IA.

Things to consider for next time: 
  - require IA to number the issues for easier reference. 
  - require IA to specify the full file name, did this sometimes, not always

Files mentioned:

ittage_cntrl_alloc_rules.md :: - alloc_rules.md:76 
ittage_table_entry_formats.md
ittage_table_interfaces.md
bp_arb_spec.md
ittage_interfaces.md
ras.sv
bp_cluster.md
bp_history_decisions.md vs bp_cluster.md

The issue below is an important catch.
  - Cross-doc / JALR split (req 5):

Unfortunately the IA has resorted to jargon "but ittage_interfaces.md gates
INDIRECT_CALL out of" 

"gates INDIRECT_CALL out of" is not a precise or actionable engineering 
phrase. And not even reasonable english.


## Claude.ai Assessment

## Follow-on Actions
- [ ] PA interactive session to resolve issues found

## CLAUDE.md Updates
- [ ] Copy some of the provisions against jargon from 
      planning/PA_PROJECT_INSTRUCTIONS.md to CLAUDE.md

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
INFRA-010

## Context Loaded
@planning/arch/ittage_cntrl_alloc_rules.md
@planning/arch/ittage_cntrl_ctr_update_rules.md
@planning/arch/ittage_cntrl_decisions.md
@planning/arch/ittage_cntrl_uaon_update_rules.md
@planning/arch/ittage_cntrl_use_update_rules.md
@planning/arch/ittage_table_entry_formats.md
@planning/arch/ittage_table_hash_rules.md
@planning/arch/ras_decisions.md
@planning/arch/bp_history_decisions.md
@planning/arch/bp_cluster.md
@planning/arch/bp_arb_spec.md
@planning/arch/sram_init.md
@planning/interfaces/ittage_interfaces.md
@planning/interfaces/ittage_table_interfaces.md
@planning/interfaces/ras_interfaces.md
@planning/testbenches/manual_tb_decisions.md
@rtl/core/frontend/bpu/rtl/ittage.sv
@rtl/core/frontend/bpu/rtl/ittage_cntrl.sv
@rtl/core/frontend/bpu/rtl/ittage_table.sv
@rtl/core/frontend/bpu/rtl/ras.sv
@rtl/core/frontend/bpu/rtl/bp_history.sv
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/core/frontend/bpu/tb/tb_ittage.sv
@rtl/core/frontend/bpu/tb/tb_ittage_cntrl.sv
@rtl/core/frontend/bpu/tb/tb_ittage_table.sv
@rtl/core/frontend/bpu/tb/ittage_assert.sv
@rtl/core/frontend/bpu/tb/ittage_assert_bind.sv
@rtl/core/frontend/bpu/tb/tb_ras.sv
@rtl/core/frontend/bpu/Makefile
@rtl/lib/rtl/bw_ram.sv
@rtl/lib/rtl/dual_lm1.sv
@rtl/lib/rtl/sat_alu.sv
@rtl/lib/rtl/sram_init.sv

## Hypothesis

The ITTAGE and RAS planning documents are believed current. ITTAGE
completed BP-034 through BP-042 (session-038 and earlier) and has
not been touched since except for shared-package changes; RAS
completed BP-062 through BP-064 (session-050). This task tests that
belief against the actual shipped RTL/tb/build files, and
additionally tests whether shared-document descriptions of the
ITTAGE/RAS/FTB three-way JALR role split remain mutually consistent.

## Background

ITTAGE and RAS are grouped together because both are consumers in
the FTB-gated target-selection scheme for JALR-family branches (FTB:
fixed-target JALR; RAS: return-convention JALR/C.JR/C.JALR; ITTAGE:
remaining history-dependent indirect JALR), and both interact with
bp_history's folded-history output (ITTAGE for its tagged-table
hashing; RAS does not consume folds but shares the checkpoint/
rollback discussion in bp_history_decisions.md). This audit precedes
bp_cluster top level design, which will treat these planning
documents as the interface authority for instantiating ITTAGE and
RAS in the cluster.

As with group 2 (tage, sc), shared documents (bp_cluster.md,
bp_arb_spec.md, bp_history_decisions.md, manual_tb_decisions.md,
sram_init.md) are NOT to be skipped even if their ITTAGE/RAS content
appears to be already tracked by open technical debt items. Open the
documents and read the ITTAGE/RAS-relevant sections in full.

## Binding Previous Decisions

None. This is a read-only audit; no design decisions are made or
overridden.

## Specific Requirements

1. Read every planning document listed in Context Loaded. For the
   shared documents (bp_cluster.md, bp_arb_spec.md,
   bp_history_decisions.md, manual_tb_decisions.md, sram_init.md),
   read the ITTAGE- and RAS-relevant sections in full -- do not skip
   a shared document on the basis that its content is already
   tracked by an open TD. If a section is genuinely irrelevant to
   ITTAGE/RAS (e.g. an FTB-, TAGE-, or SC-only section), note that
   it was scoped out and why.
2. Read the associated RTL, package (ITTAGE/RAS-relevant portions
   only), testbenches, and Makefile (ITTAGE/RAS targets only) files.
3. For each lib component listed, first confirm ITTAGE or RAS
   actually instantiates it before reviewing it. Skip any that
   neither uses.
4. Compare planning document claims (port lists, parameter names and
   values, field definitions, behavioral rules, module structure)
   against what the RTL/tb/Makefile actually contain, for ITTAGE and
   RAS independently.
5. Specifically verify the JALR three-way split: confirm
   bp_cluster.md's description of the FTB/RAS/ITTAGE role split
   (fixed-target vs return-convention vs history-dependent indirect)
   is consistent with ras_decisions.md, ras_interfaces.md,
   ittage_cntrl_decisions.md, and ittage_interfaces.md. Report any
   place these documents disagree on which unit handles which case.
6. Verify ITTAGE's fold consumption (index/tag hashing for IT1-IT4)
   against bp_history_decisions.md's canonical fold definition and
   bp_history.sv's actual output ports, the same way TAGE's fold
   consumption was checked in the group 2 audit.
7. Verify bp_arb_spec.md's RAS non-RAM model (section 7.2: no PQ/UQ/
   arbiter, TOS read at p0, push/pop at p2, snapshot-based recovery)
   is consistent with ras.sv's actual port list and behavior, and
   that bp_arb_spec.md's ITTAGE arbitration parameters (section 5.4)
   are consistent with ittage.sv.
8. Report only actionable discrepancies: something a planning doc
   states that the code does not do, or vice versa, or two documents
   that disagree with each other, that would mislead someone using
   these docs as the interface/behavior authority.
9. Do not report items that require no action, and do not report
   items already flagged or resolved elsewhere in the documents
   themselves (e.g. an open TD or BP Cluster Open TBD already
   tracking the gap).

## Constraints

- Read-only. Do not modify, create, or delete any file.
- This is a light sanity check, not a deep-dive audit. Do not
  exhaustively re-derive every signal; check for drift between doc
  claims and code reality, and between documents that describe the
  same interface or role split.
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

## Summary

Group 3 of 3 planning-doc audit (ittage, ras). Read-only. All 42
Context Loaded files opened and compared doc-vs-code and doc-vs-doc.
Actionable discrepancies below; already-tracked items (TD #49, #78,
#96, PHR TBD, flush _px signals) excluded per requirement 9. dual_lm1
and sat_alu confirmed NOT instantiated by ITTAGE/RAS (scoped out).
Makefile ITTAGE/RAS targets and used lib components (bw_ram,
sram_init) are clean.

ITTAGE (doc vs RTL):
- alloc_rules.md:76 gives the alloc write-data field order as
  [TAG,EPC,USE,CTR,TGT,VALID]. Authoritative entry_formats.md:31 +
  ittage_table.sv:15-21 + the write assembly in ittage_cntrl.sv:844-
  851 are MSB..LSB TAG,TGT,EPC,USE,CTR,VALID. Doc misplaces TGT and
  EPC; building alc_wd_u0 from it yields a corrupt entry.
- ittage_table_entry_formats.md:57 says TAG width is IT_TBL_TGT_WIDTH
  (the 38b target width). TAG width is IT_TBL_TAG[t]={8,8,9,9,11}
  (bp_defines_pkg.sv:303), as the same doc's line 53 correctly cites.
- Interface docs describe one target-write strobe tgt_wr_u0
  (ittage_table_interfaces.md:248,392-394; ittage_interfaces.md:358-
  384). RTL split it into prm_tgt_wr_u0 / alt_tgt_wr_u0
  (ittage_table.sv:87-88, driven ittage_cntrl.sv:79-80,798-824). A
  single tgt_wr_u0 port no longer exists.
- ittage_table_interfaces.md:35-38 says up to 2 components' CTR ("4
  total writes") may be written per update. RTL writes only the
  provider's CTR (prm XOR alt, ittage_cntrl.sv:665-718), matching
  ctr_update_rules.md and the same doc's own :257-260. Line 35-38
  prose is stale.
- bp_arb_spec.md 5.4 (:355-364): lists ITTAGE_RESP_BUF_DEPTH as a
  live arb param, but the response buffer was removed (BP-038b,
  ittage.sv:16-17) -- param is now vestigial. Line 364 names
  ittage_redir_val_p2 as the override signal; ITTAGE has no redirect
  output port (consumer raises s2_redirect, ittage_interfaces.md:262-
  263).
- ittage_interfaces.md:279 calls the init value ITTAGE_SRAM_INIT_VALUE;
  actual package/RTL name is IT_SRAM_INIT_VALUE (bp_defines_pkg.sv:321,
  ittage.sv:112).

RAS (doc vs RTL):
- ras.sv:44 declares input ras_pc_p2 (driven by tb_ras.sv:54,85) but
  the LOCKED port list in ras_interfaces.md section 4 (:94-161) omits
  it. Also note: ras_pc_p2 is declared-but-unread inside ras.sv, so it
  is either dead or an undocumented planned input -- doc and RTL
  disagree either way.
- ras_decisions.md:448-450 names the commit pointer param
  RAS_COMMIT_PTR_WIDTH and says "not yet in bp_defines_pkg.sv". Actual
  name is RAS_COMMIT_PTR_BITS, defined bp_defines_pkg.sv:352, used
  ras.sv:103. ras_interfaces.md:66 already has the correct name; only
  the decisions doc is stale.

Cross-doc (JALR three-way split, requirement 5):
- Indirect-CALL ownership disagreement. bp_cluster.md:111-116 defines
  ITTAGE as target predictor for indirect NON-return branches
  (includes indirect calls) and :440-443 places it_indirect_call in
  the ITTAGE meta. But ittage_interfaces.md:30-34,264-266 states
  ITTAGE operates exclusively on indirect branches that are neither
  CALL nor RETURN, gating out INDIRECT_CALL (RAS "exclusively"). The
  target predictor for a history-dependent indirect call is therefore
  ambiguous, and the it_indirect_call ITTAGE meta field contradicts
  ittage_interfaces' gating rule. Not tracked by any open TD.

Fold consumption (requirement 6):
- IT1-IT4 fold widths/ports agree across bp_cluster.md:119-122,
  bp_defines_pkg.sv:299-303, and bp_history.sv (it_t1..it_t4 idx/fh1/
  fh2). IT5 disagrees:
  - No-folds authority: bp_history_decisions.md:41-42,502-503 (canon:
    folds for IT1-IT4 only; "ITTAGE IT5 (BrIMLI) have no folds"),
    bp_cluster.md:123-124,313, and bp_history.sv (never assigns
    it_t5_* -- no IT5 fold generation anywhere).
  - Folded camp: bp_structs_pkg.sv:61-63 (it_t5_idx_fh/tag_fh1/tag_fh2
    exist), bp_defines_pkg.sv:299-303 (IT5 non-zero fold widths),
    ittage_interfaces.md:167 and its II1 entry :439-444 (marked
    Complete, asserts the no-folds comment was "incorrect" and folds
    were added), ittage_table_hash_rules.md:42-48,62-64 (IT5 hashed
    like the rest).
  - Effect: ittage.sv:511-513 wires IT5 to it_t5_* folds that
    bp_history.sv never drives -> permanently 0. Either RTL is missing
    IT5 fold generation or the interface/hash/struct docs are wrong.
    Also bp_history_decisions.md:502-503's bp_folded_hist_t
    description (IT1-IT4 only) omits the it_t5 fields the struct
    actually carries. Not tracked by any open TD.

## Test Matrix (testbench sessions only, omit otherwise)
N/A

## What was delivered
N/A

## Test Case Results
N/A

## Assumptions made not explicit in the prompt
- "Actionable" = a doc claim the code contradicts (or vice versa), or
  two docs that disagree, that would mislead someone using the docs as
  interface/behavior authority. Cosmetic/no-action drift excluded.
- Items already acknowledged inside the docs (open TD numbers, BP
  Cluster Open TBDs, in-doc "incorrect/deferred" notes) excluded, per
  requirement 9, EXCEPT where a doc marks an item resolved on the
  wrong side of a live doc-vs-code contradiction (IT5 folds), which is
  reported because the resolution does not match the RTL.
- bp_arb_spec.md 7.2 section header taken to start at line 473 (## 7 at
  461); 5.4 at lines 355-364.

## Decisions made not explicit in the prompt
N/A

## RVA23 compliance risks and gaps noticed
None specific to RVA23. The JALR indirect-call ownership ambiguity and
the IT5 fold contradiction are microarchitecture/doc-consistency
issues, not profile-compliance gaps.

## Deferred Work
N/A -- read-only audit. No fixes attempted; discrepancies above are
handed off for the owning module tasks / bp_cluster design to resolve.

## Other Notes
- Minor / low-impact (not counted among the actionable set):
  - sram_init.md consumer lists (:152-166) name ittage.sv +
    ittage_table.sv as consumers and loop_pred.sv as a confirmed
    non-consumer, but omit RAS from both lists. RAS is register-file
    based (no SRAM; ras_interfaces.md:42, ras_decisions.md:70), so the
    omission is harmless but incomplete.
  - bp_arb_spec.md 7.2 phrases the p0 TOS read as gated on "a return
    detected at p0"; ras.sv:138-152 presents TOS unconditionally with
    type-gating deferred to the consumer. Wording imprecision only.
  - manual_tb_decisions.md is a generic manual-TB structure doc;
    ITTAGE-specific TB decisions are delegated to ittage_mtb_decisions
    (:30) and no RAS-specific TB content lives here -- scoped out.
- Makefile: ITTAGE/RAS lint/sim targets (lint/sim_ittage_table,
  _ittage_cntrl, _ittage, _ras) reference only existing source files
  and carry the required project flags (-Wno-IMPORTSTAR, -Wno-UNUSED,
  --timing in VER_FLAGS; -Wno-DECLFILENAME in SIM_EXTRA_FLAGS). Not
  run (read-only task). No issues.

## Files Modified
None (read-only task).

# Context Usage Report

Model: claude-opus-4-8[1m] (Opus 4.8, 1M context)
Total: 61.5k / 1,000k tokens (6% used, 94% free)

## Usage by category

| Category            | Tokens | Percent |
|---------------------|--------|---------|
| System prompt       | 2.8k   | 0.3%    |
| System tools        | 16k    | 1.6%    |
| MCP tools           | 1.5k   | 0.1%    |
| Memory files        | 3.8k   | 0.4%    |
| Skills              | 2k     | 0.2%    |
| Messages            | 36.9k  | 3.7%    |
| Free space          | 938.5k | 93.9%   |

## Notes

- Messages (36.9k) is the bulk of used context: the INFRA-010 prompt,
  tool calls, and the four audit agents' returned summaries.
- The audit subagents consumed ~369k tokens reading all 42 Context
  Loaded files, but ran in isolated contexts; only their compact final
  reports entered this session. Fan-out kept main-context cost low.

:: RESULTS:END ::

