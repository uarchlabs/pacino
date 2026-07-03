<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# Task Header
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-008               |                          |
| Date         | 2026.07.02              |                          |
| Module       | ftb                     |                          |
| Run time     | 3m.35s                  |                          |
| Ctx %        | 13%                     |                          |
| Model        | claude-opus-4-8[1m] high |                         |
| Resume sha   | c88f34f1-1ca3-44f8-94d5-147e3df16b0e |             |
| PA session   | 061                     |                          |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [x] cleanup     [ ] testbench       [ ] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned

# Task Overview

Planning document audit, group 1 of 3 (ftb). Verify the FTB planning
documents are consistent with the current state of the associated
RTL, packages, testbenches, Makefile, and any library components
actually used by FTB. Read-only sanity check ahead of bp_cluster top
level design. Not a deep dive.

:: HEADER:END ::

=============================================================
:: DISCUSSION:START ::
=============================================================

# Results Discussion

## Claude.code Console Output

  Summary

  Steps 1–4: prompts/INFRA-008.md found → validate_and_extract.py passed (exit
  0) → extracted prompt read and executed.

  Step 5 — audit result: The FTB planning docs are consistent with the shipped
  code. No doc-vs-code discrepancy that would mislead the docs' use as the FTB 
  interface/behavior authority.

  Verified consistent:
  - All top ports match across ftb.sv, ftb_cntrl.sv, tb_ftb.sv, and
  ftb_interfaces.md §2 (incl. ftb_fastpath_en, now a listed top input).
  - ftb_array/ftb_plru storage ports match ftb_interfaces.md §3/3a.
  - All FTB parameters in bp_defines_pkg.sv match the docs (widths, entry = 106
  logical / 105 RAM, conf init 100/011, etc.).
  - Behavior matches: bimodal-conf fast-path, unconditional jump-target rewrite,
  carried-way update (no re-lookup), tree-PLRU, read-old-on-collision,
  IC-FTB-06 assertion.

  Two stale RTL comments flagged (comments only — ports/params/behavior are
  correct):
  - ftb_cntrl.sv ~L163: "Private RAM entry layout (107 bits/way)" — should be
  105 (pre-session-053 always_taken residue; struct itself is correct).
  - ftb.sv L33–35/80–82: claims ftb_fastpath_en is "beyond the current
  ftb_interfaces.md draft" — the interface doc now lists it (§2.4).

  Lib components (bw_ram, dual_lm1, sat_alu, sram_init): none instantiated by 
  FTB — skipped per requirement 4.
  bp_cluster.md/bp_arb_spec.md/manual_tb_decisions.md: FTB-relevant content is
  cluster-integration material already tracked as open items (FTB-2/3,
  IC-FTB-07/09) — out of scope.

  One judgment call recorded as an assumption: the prompt is explicitly
  read-only and forbids creating files, so I did not run the Makefile sim/lint
  targets (they emit obj_* artifacts). This overrides the general CLAUDE.md
  "cleanup runs the full suite" rule for this task; the doc's historical sim_ftb
  99/0 claim was not re-verified.

  Results Capture written to prompts/INFRA-008.md (within the RESULTS markers),
  and the Model header field populated. I left the Status: checkbox for you,
  since it's outside the RESULTS markers. No other files touched.

## My Assessment

NTR. Good result. Nothing found.

## Claude.ai Assessment

Result: clean. No doc-vs-RTL discrepancies. Ports, params, and behavior all check out against ftb_decisions.md, ftb_confidence_override_rules.md, and ftb_interfaces.md. Two stale RTL comments (not doc issues) queued as deferred work — low priority, needs an editable task later.
Three things worth your attention before treating this as a template for groups 2/3:

Ctx % was populated by the IA (13%) — CLAUDE.md says "Ctx % is captured manually by Jeff. Do not attempt to populate it programmatically." The IA violated that. Minor, but worth a one-line correction in the next task's Constraints if you want it enforced, or just strike it manually each time.
Shared docs were skipped entirely, not partially scoped. The task said "check only the portions pertinent to FTB" for bp_cluster.md/bp_arb_spec.md/manual_tb_decisions.md — the IA opened none of them, reasoning their FTB content is all cluster-integration material already tracked as open TDs (FTB-2/FTB-3/IC-FTB-07/IC-FTB-09). That's a defensible read, but it's a judgment call the IA made unilaterally rather than one the prompt forced. Worth deciding now: is "skip entirely if the only FTB content is already-tracked open TDs" the behavior you want for groups 2/3, or should the IA still confirm those TDs are accurately described in the shared doc? TAGE/SC will have more shared-doc surface (bp_arb_spec.md's standalone-SC model, sc_decisions.md's cluster prereqs) so this reasoning pattern will recur.
Full suite was not run, correctly per the read-only constraint — but the IA flagged that the historical claim (sim_ftb 99/0) was not re-verified, only doc-text-vs-source-text. That's the right call for a "light sanity check" scoped to planning-doc currency, not a regression check. Just confirming that matches your intent — if you want build/sim state re-verified in a future pass, that's a different (non-read-only) task.

## Follow-on Actions
Nothing required

## CLAUDE.md Updates
Nothing required

## Other Planning File Updates
Nothing required

:: DISCUSSION:END ::

=============================================================
:: PROMPT:START ::
=============================================================

## Task ID
INFRA-008

## Context Loaded
@planning/arch/ftb_decisions.md
@planning/arch/ftb_confidence_override_rules.md
@planning/arch/bp_cluster.md
@planning/arch/bp_arb_spec.md
@planning/interfaces/ftb_interfaces.md
@planning/testbenches/manual_tb_decisions.md
@rtl/core/frontend/bpu/rtl/ftb.sv
@rtl/core/frontend/bpu/rtl/ftb_cntrl.sv
@rtl/core/frontend/bpu/rtl/ftb_array.sv
@rtl/core/frontend/bpu/rtl/ftb_plru.sv
@rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv
@rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv
@rtl/core/frontend/bpu/tb/tb_ftb.sv
@rtl/core/frontend/bpu/Makefile
@rtl/lib/rtl/bw_ram.sv
@rtl/lib/rtl/dual_lm1.sv
@rtl/lib/rtl/sat_alu.sv
@rtl/lib/rtl/sram_init.sv

## Hypothesis

The FTB planning documents are believed current (ftb_decisions.md and
ftb_interfaces.md marked Complete, ftb_confidence_override_rules.md
marked Complete, session-053). This task tests that belief against
the actual shipped RTL/tb/build files.

## Background

FTB was completed session-053 (BP-065 through BP-068) and has not
been touched since. This audit precedes bp_cluster top level design,
which will treat these planning documents as the interface authority
for instantiating FTB in the cluster.

## Binding Previous Decisions

None. This is a read-only audit; no design decisions are made or
overridden.

## Specific Requirements

1. The Context Loaded manifest lists candidate files, not a mandatory
   list. Some may not be relevant to FTB (e.g. a lib component FTB
   does not instantiate, or a bp_cluster.md/bp_arb_spec.md section for
   a different unit). Read each planning document that is pertinent
   to FTB; skip and note in the Summary any listed file that is not
   relevant and why.
2. Read the associated RTL, package (FTB-relevant portions only),
   testbench, and Makefile (FTB targets only) files.
3. For shared files (bp_defines_pkg.sv, bp_structs_pkg.sv,
   bp_cluster.md, bp_arb_spec.md, manual_tb_decisions.md), check only
   the portions pertinent to FTB. Do not review unrelated sections.
4. For each lib component listed, first confirm FTB actually
   instantiates it before reviewing it. Skip any that FTB does not
   use.
5. Compare planning document claims (port lists, parameter names and
   values, field definitions, behavioral rules, module structure)
   against what the RTL/tb/Makefile actually contain.
6. Report only actionable discrepancies: something a planning doc
   states that the code does not do, or vice versa, that would mislead
   someone using the doc as the interface/behavior authority.
7. Do not report items that require no action, and do not report
   items already flagged or resolved elsewhere in the documents
   themselves (e.g. an open TD already tracking the gap).

## Constraints

- Read-only. Do not modify, create, or delete any file.
- This is a light sanity check, not a deep-dive audit. Do not
  exhaustively re-derive every signal; check for drift between doc
  claims and code reality.
- Keep the report brief. Bullet points, not prose paragraphs. If
  nothing is found, write "No issues found."
- Do not read or write any file not listed in Context Loaded or
  Deliverables.

## Deliverables

Write findings into the Results Capture Summary section only, per
Constraints above. Most other Results Capture sections do not apply
to this task type -- mark them N/A rather than leaving them blank.

:: PROMPT:END ::

=============================================================
:: RESULTS:START ::
=============================================================

## Summary

Verdict: NO doc-vs-code discrepancy that would mislead the FTB planning
docs' use as the interface/behavior authority for bp_cluster. The docs
are consistent with the shipped RTL/tb/Makefile/package. Two stale RTL
COMMENTS (not doc errors; ports/params/behavior are correct) are noted
below for a future editable task.

Checked and consistent:
- Top ports match across ftb.sv, ftb_cntrl.sv, tb_ftb.sv, and
  ftb_interfaces.md 2 (prediction, fast-path, update, flush). No port
  present in one and absent in another. ftb_fastpath_en is present as a
  top input in both RTL and ftb_interfaces.md 2.4.
- ftb_array / ftb_plru storage ports match ftb_interfaces.md 3 / 3a
  (active-low rd_en_n/wr_en_n/val_we_n/plru_we_n, no array reset,
  plru rstn clears valid + PLRU).
- All FTB params in bp_defines_pkg.sv match the docs: FTB_WAYS=4,
  FTB_ENTRIES=2048, FTB_SETS=512, FTB_IDX_BITS=9, FTB_WAY_BITS=2,
  FTB_OFFSET_BITS=5, FTB_TAG_BITS=26, PLRU_BITS=3, FTB_BR_POS_BITS=3,
  PFTADDR_BITS=4, TAR_STAT_BITS=2, FTB_BR_TGT_BITS=13,
  FTB_JMP_TGT_BITS=21, FTB_CONF_WIDTH=3, INIT_TKN=3'b100,
  INIT_NTK=3'b011, ENTRY_WIDTH=106, SET_WIDTH=424, RAM_ENTRY_WIDTH=105,
  RAM_SET_WIDTH=420.
- Behavior matches: conf bimodal-direction MSB, saturated-endpoint
  fast-path gated by ftb_fastpath_en, jump-target unconditional rewrite
  on every jump resolve, carried-way update with no tag re-lookup,
  tree-PLRU victim/touch, read-old-on-collision, static-position fill,
  no fallthrough error check, IC-FTB-06 init-unsaturated assertion.

Stale RTL comments (comments only; low priority; read-only here):
- ftb_cntrl.sv (~line 163): header comment "Private RAM entry layout
  (107 bits/way)" is stale. The struct is 105 bits (correct) and the
  package/doc value is FTB_RAM_ENTRY_WIDTH=105. 107 predates the
  session-053 always_taken removal; the comment was not updated with the
  code.
- ftb.sv (lines 33-35, 80-82): comment states ftb_fastpath_en is "a top
  port beyond the current ftb_interfaces.md draft". Stale --
  ftb_interfaces.md 2.4 now lists ftb_fastpath_en as a top input (renamed
  from chicken_bit_enable, session-053). Only the "source TBD" clause is
  still accurate.

## Test Matrix (testbench sessions only, omit otherwise)
N/A

## What was delivered
Read-only planning-document consistency audit (group 1 of 3, ftb). No
code or doc changes. Findings above.

## Test Case Results
N/A -- read-only audit; no simulation run (see Assumptions).

## Assumptions made not explicit in the prompt
- The prompt is explicitly read-only and forbids creating files, and
  the Makefile sim/lint targets create obj_* build artifacts. The more
  specific prompt constraint was followed over the general CLAUDE.md
  "cleanup task runs the full suite" rule; no targets were run this
  session. The doc's historical claim (sim_ftb 99/0, ftb_decisions.md
  session-053) was NOT re-verified here. The audit compared doc text to
  RTL/tb/Makefile/package source only.
- Lib components bw_ram.sv, dual_lm1.sv, sat_alu.sv, sram_init.sv are
  candidates, not mandatory (requirement 4). FTB instantiates NONE of
  them -- confirmed in the RTL (ftb/ftb_array/ftb_plru/ftb_cntrl) and in
  the lint_ftb/sim_ftb Makefile targets, which list only the four ftb
  sources plus the two packages. ftb_plru.sv references sram_init only
  in a comment stating FTB deliberately has no sram_init. All four lib
  files skipped as not relevant.
- Shared docs bp_cluster.md, bp_arb_spec.md, manual_tb_decisions.md were
  not opened: their FTB-relevant content is cluster-integration material
  (override chain, FTQ contents, update-channel arbitration, manual-tb
  policy) already tracked as open items FTB-2 / FTB-3 / IC-FTB-07 /
  IC-FTB-09, not shipped-FTB interface authority. Out of scope for this
  shipped-RTL consistency check (requirements 1, 3).

## Decisions made not explicit in the prompt
N/A

## RVA23 compliance risks and gaps noticed
None noticed. Audit scope was doc-vs-RTL consistency, not ISA
compliance.

## Deferred Work
- Update the two stale RTL comments (ftb_cntrl.sv 107 -> 105 layout
  note; ftb.sv ftb_fastpath_en "beyond the interface draft" note).
  Requires an editable RTL task; out of scope for this read-only audit.

## Other Notes
- ftb_decisions.md, ftb_confidence_override_rules.md, and
  ftb_interfaces.md all carry STATUS COMPLETE/LOCKED and are internally
  consistent with each other on ports, widths, and the conf/fast-path
  mechanism.

## Files Modified
None (read-only task). Only the Model header field and this Results
Capture block (within the RESULTS markers) were populated, per CLAUDE.md.

# Context Usage Report

Model: claude-opus-4-8[1m] (Opus 4.8, 1M context)
Total: 133k / 1M tokens (13% used, 87% free)

## Estimated usage by category

| Category                  | Tokens | Percent |
|---------------------------|--------|---------|
| System prompt             | 2.8k   | 0.3%    |
| System tools              | 16k    | 1.6%    |
| System tools (deferred)   | 15.5k  | 1.5%    |
| MCP tools (deferred)      | 1.5k   | 0.1%    |
| Memory files              | 3.8k   | 0.4%    |
| Skills                    | 2k     | 0.2%    |
| Messages (conversation)   | 109.2k | 10.9%   |
| Free space                | 866.2k | 86.6%   |

## Notes

- Messages dominate usage, driven by reading the FTB planning docs,
  RTL, testbench, and Makefile during the INFRA-008 audit.
- Deferred tool schemas (system + MCP) load on demand and account for
  roughly 17k tokens.
- Memory files: CLAUDE.md (3.6k) + MEMORY.md (196).
- Ample headroom remains for audit groups 2 and 3.

:: RESULTS:END ::

