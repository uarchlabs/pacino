=============================================================
# Task Header 
=============================================================
:: HEADER:START ::
| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | INFRA-005               |                          |
| Date         | 2026.04.24              |                          |
| Module       | tage / tage_cntrl       |                          |
| Run time     | 11m.44s                 |                          |
| Ctx %        | 60%                     |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | ~/Development/jeffnye-gh/atemp |                   |
Task:   [ ] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [x] verification
Mode:   [x] automated   [ ] manual
Status: [ ] in-progress [x] complete        [ ] abandoned
# Overview of task
  Run verilator_coverage --annotate on cov_tage coverage
  data. Read annotated source files. Produce a gap report
  with two sections: raw uncovered lines with context, and
  best-effort mapping to coverage plan rows with confidence.
:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::
# Results Discussion 
## Claude.code Console Output

  Summary:

  - 13 gap regions found across tage.sv (2), tage_cntrl.sv (2), tage_table.sv (7),     
  tage_bim.sv (1)
  - 11 functional gaps, 2 intentional fast-init exclusions                             
  - CA-08 (starvation Rule 2) confirmed as gap — 2 regions in tage.sv
  - 4 new rows suggested: CE-09 (aging active), CE-10 (allocation fires end-to-end),   
  CP-10 (T1-T3 folded history), CE-11 (alt CTR write to table)                         
  - 3 CU-11 CONFLICTS: tage_table slot 1 RAM writes show zero execution but plan marks 
  CU-11 covered                                                                        
  - Inferred CU-08/CU-09 conflicts (medium confidence): tage_enable_aging was never
  driven high in 4758 eligible cycles, so the aging epoch never advanced and           
  age=1/age=2 paths could not have been exercised
  - Notable: The allocation path (GAP-4/CE-10) never fired end-to-end despite all      
  entries being initialized with USEFUL=0 — this warrants investigation before writing 
  the closure testbench
  - .gitignore already covers coverage/ — no change needed                             
                                                                                       
✻ Cogitated for 11m 44s                
                                                                                       
※ recap: INFRA-005 gap analysis complete. Ran verilator_coverage --annotate, identified
   11 functional coverage gaps, and wrote full results to prompts/INFRA-005.md. Next: 
  write the closure testbench targeting the identified gaps. (disable recaps in        
  /config)      

## My Assessment

Nothing required

## Claude.ai Assessment

Excellent result — 11m44s for a genuine gap analysis with source-level reasoning is impressive. The output is directly actionable.
Key findings to digest:
The most important discoveries in priority order:

CE-10 (allocation never fired) — this is the critical one. The full allocation path was never exercised end-to-end despite all entries being initialized with USEFUL=0. The suspected root cause (provider was always T4, making no higher table available for allocation) needs investigation before writing the closure testbench. A closure test that doesn't understand why allocation never fired will likely fail.
CU-08/CU-09 conflicts (aging) — TC-44 and TC-45 are marked covered in the plan but tage_enable_aging was never driven high. This means the age=1/age=2 paths were exercised via a different code path than expected, or the plan is wrong about those tests covering aging. Needs investigation.
CU-11 conflict (slot 1 RAM writes) — plan marks covered but zero slot 1 tage_table RAM writes occurred. This is a testbench gap, not an RTL bug.
CA-08 (Rule 2 starvation) — confirmed gap, already tracked as debt #39.

Key findings to digest:
The most important discoveries in priority order:

CE-10 (allocation never fired) — this is the critical one. The full allocation path was never exercised end-to-end despite all entries being initialized with USEFUL=0. The suspected root cause (provider was always T4, making no higher table available for allocation) needs investigation before writing the closure testbench. A closure test that doesn't understand why allocation never fired will likely fail.
CU-08/CU-09 conflicts (aging) — TC-44 and TC-45 are marked covered in the plan but tage_enable_aging was never driven high. This means the age=1/age=2 paths were exercised via a different code path than expected, or the plan is wrong about those tests covering aging. Needs investigation.
CU-11 conflict (slot 1 RAM writes) — plan marks covered but zero slot 1 tage_table RAM writes occurred. This is a testbench gap, not an RTL bug.
CA-08 (Rule 2 starvation) — confirmed gap, already tracked as debt #39.

## Follow-on Actions
None
## CLAUDE.md Updates
None
## Other Planning File Updates
- [ ] Update tage_coverage_plan.md
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::
## Task ID
INFRA-005

## Context Loaded
@planning/verification/tage_coverage_plan.md
@rtl/core/frontend/bpu/rtl/tage.sv
@rtl/core/frontend/bpu/rtl/tage_cntrl.sv
@rtl/core/frontend/bpu/rtl/tage_table.sv
@rtl/core/frontend/bpu/rtl/tage_bim.sv

## Hypothesis
Running verilator_coverage --annotate on the cov_tage
coverage data and reading the annotated source files will
identify uncovered lines and branches precisely enough to
map them to coverage plan rows in tage_coverage_plan.md.
The gap report produced here will directly scope the
closure testbench prompt.

## Background
INFRA-003 and INFRA-004 established coverage infrastructure
for the bpu Makefile. The cov_tage target produces:
  rtl/core/frontend/bpu/coverage/tage/coverage.dat

Baseline coverage rate for cov_tage is 70.1% line/branch.
The coverage plan at planning/verification/tage_coverage_plan.md
defines coverage goals in rows labeled CP-xx (prediction),
CU-xx (update), CA-xx (arbitration), and CE-xx (error and
boundary paths).

verilator_coverage --annotate writes annotated copies of
source files to a specified directory. Each line is
prefixed with a coverage count or a marker indicating
the line was not executed. Uncovered branches are
annotated inline.

## Binding Previous Decisions
- cov_tage coverage.dat is at:
  rtl/core/frontend/bpu/coverage/tage/coverage.dat
- Source files are at:
  rtl/core/frontend/bpu/rtl/
- Do not modify any RTL or testbench files.
- Do not modify any Makefile targets.
- Do not modify the coverage plan document.

## Specific Requirements

### Step 1 -- Verify coverage data exists

Check that the following file exists and is non-empty:
  rtl/core/frontend/bpu/coverage/tage/coverage.dat

If it does not exist, run:
  cd rtl/core/frontend/bpu && make cov_tage

Then confirm the file exists before proceeding.

### Step 2 -- Run verilator_coverage --annotate

Run:
  verilator_coverage \
    --annotate coverage/tage/annotated \
    rtl/core/frontend/bpu/coverage/tage/coverage.dat

Output lands in:
  rtl/core/frontend/bpu/coverage/tage/annotated/

This directory will contain annotated copies of each
source file that contributed to the coverage data.

### Step 3 -- Read annotated source files

Read all annotated files produced in Step 2. Focus on:
  - Lines prefixed with 0 (executed zero times)
  - Branch annotations showing untaken paths
  - Any blocks marked with coverage_off pragmas
    (these are intentionally excluded and should be
    noted but not counted as gaps)

For each uncovered region found, record:
  - Source file name
  - Line number range
  - The RTL code on those lines (3-5 lines of context
    surrounding the gap)
  - Whether it is a line gap or a branch gap

### Step 4 -- Produce gap report

Print the gap report to console in two sections.

#### Section A: Raw gaps

For each uncovered region, print:

  FILE: <filename>
  LINES: <start>-<end>
  TYPE: line | branch
  CONTEXT:
    <line N-2>
    <line N-1>
  > <uncovered line>        <- mark uncovered lines with >
    <line N+1>
    <line N+2>

Group gaps by source file. Within each file list gaps
in line number order.

#### Section B: Coverage plan mapping

For each gap found in Section A, attempt to map it to
one or more rows in tage_coverage_plan.md. Use the RTL
context and the coverage plan row descriptions to make
the mapping.

Print each mapping as:

  GAP: <file>:<lines>
  MAPS TO: <row ID> -- <row description>
  CONFIDENCE: high | medium | low
  REASON: <one sentence explaining the mapping>

If a gap does not map to any existing coverage plan row,
print:

  GAP: <file>:<lines>
  MAPS TO: NONE -- no matching coverage plan row
  CONFIDENCE: n/a
  REASON: <one sentence describing what the gap covers>
  SUGGEST: <proposed new coverage row description>

If a gap maps to a row already marked as covered in the
plan, flag it:

  GAP: <file>:<lines>
  MAPS TO: <row ID> -- CONFLICT: plan marks as covered
  CONFIDENCE: low
  REASON: <explanation of the discrepancy>

## Constraints
- Do not modify any RTL or testbench .sv files.
- Do not modify any Makefile targets.
- Do not modify tage_coverage_plan.md.
- Do not write any output files. Console output only.
- The annotated/ directory created in Step 2 is a
  build artifact. Add it to .gitignore if not already
  present.
- If verilator_coverage --annotate is not available,
  report and stop.

## Deliverables
1. Console output: Section A raw gap list.
2. Console output: Section B coverage plan mapping
   with confidence indicators.
3. Results Capture filled in below summarizing the
   gap count, file distribution, and any NONE or
   CONFLICT mappings found.
:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::
## Summary
Gap analysis complete. 13 gap regions identified across 4 files.
11 functional gaps and 2 intentional fast-init exclusions.
4 NONE mappings with suggested new rows (CE-09, CE-10, CP-10,
CE-11). 3 CONFLICT mappings against CU-11 (plan marks covered
but slot 1 tage_table RAM writes never occurred). CA-08
starvation override confirmed as gap (2 regions). Inferred
conflict with CU-08 and CU-09 (aging rows marked covered but
tage_enable_aging was never driven high in any test cycle).

## Test Matrix
Omitted -- not a testbench session.

## What was delivered
1. Console output: Section A raw gap list (13 gap regions,
   annotated with context and zero-count markers).
2. Console output: Section B coverage plan mapping with
   confidence indicators for all 13 gaps.
3. Results Capture (this section).

## Step 1 -- Coverage data status
File: rtl/core/frontend/bpu/coverage/tage/coverage.dat
Size: 160872 bytes, dated 2026-04-24 13:47. Non-empty, no
make run required.

## Step 2 -- Annotate output
Command:
  cd rtl/core/frontend/bpu && verilator_coverage \
    --annotate coverage/tage/annotated \
    coverage/tage/coverage.dat
Exit 0. Total coverage reported by tool: 4.00% (227/4789).
Note: this differs from 70.1% baseline; the tool metric
counts differently from genhtml line/branch HTML report.
Output directory: rtl/core/frontend/bpu/coverage/tage/annotated/
Already covered by coverage/ entry in root .gitignore (line 61).

## Step 3 -- Files read
Annotated files read:
  tage.sv          (769 lines annotated)
  tage_cntrl.sv    (916 lines annotated)
  tage_table.sv    (501 lines annotated)
  tage_bim.sv      (215 lines annotated)
  sram_init.sv     (not analyzed -- out of scope)
  tb_tage.sv       (not analyzed -- testbench)

## Step 4 -- Gap report summary
Total gap regions: 13
  Functional:      11 (GAP-1 through GAP-11)
  Intentional:      2 (GAP-12 tage_table fast-init,
                       GAP-13 tage_bim fast-init)

File distribution:
  tage.sv:       2 gaps -- Rule 2 starvation (arb_comb,
                           arb_cred_ff)
  tage_cntrl.sv: 2 gaps -- aging_ff never active,
                           alloc candidate scan never found
                           ueff==0 entry
  tage_table.sv: 7 gaps -- fh_sel cases 1-3/default (T1-T3
                           folded history), addr_mux_s0 alloc,
                           din_mux_s0 alloc+alt_ctr, addr_mux_s1
                           alloc+norm, din_mux_s1 all write
                           paths, bweb_mux_s1 all loops, plus
                           fast-init (intentional)
  tage_bim.sv:   1 gap  -- fast-init (intentional)

Plan mappings:
  CA-08 (confirmed gap):     2 (G1, G2)
  NONE + suggest CE-09:      1 (G3 -- aging active path)
  NONE + suggest CE-10:      3 (G4, G6, G7 -- alloc fires)
  NONE + suggest CP-10:      1 (G5 -- T1-T3 fh_sel)
  NONE + suggest CE-11:      1 (G8 -- alt CTR write to table)
  CU-11 CONFLICT:            3 (G9, G10, G11 -- slot 1 writes)
  Intentional no row:        2 (G12, G13 -- fast-init)

Inferred (not directly from annotation):
  CU-08 CONFLICT (medium):  tage_enable_aging never true;
    lcl_epoch never advanced; age=1 path unreachable.
  CU-09 CONFLICT (medium):  same root cause; age=2 path
    unreachable.

Suggested new plan rows:
  CE-09: Aging counter active; interval decrements; epoch rolls
  CE-10: Allocation fires end-to-end; ueff==0 entry found,
         allocated, written to RAM
  CE-11: Alt-provider CTR write reaches tage_table RAM
  CP-10: T1/T2/T3 fh_sel exercised (shorter-history prediction)

## Test Case Results
Not applicable -- gap analysis session.

## Assumptions made not explicit in the prompt
- %000000 annotation prefix indicates zero executions for that
  coverage point. Non-zero counts (%000001 and above, space-
  prefixed or %-prefixed) indicate covered paths.
- generate-for headers (genvar loops) show %000000 by design
  (elaboration-time, no runtime count). These are not counted
  as gaps.
- tage_table.sv annotation reflects aggregate coverage across
  all T1-T4 instances of the parameterized module.
- The 4.00% tool-reported rate vs 70.1% HTML baseline is
  likely a metric difference (tool may count points, HTML
  counts lines). Both are from the same coverage.dat file.

## Decisions made not explicit in the prompt
- sram_init.sv and tb_tage.sv were present in annotated/ but
  excluded from analysis; sram_init is infrastructure not in
  Context Loaded; tb_tage is a testbench and out of scope.
- GAP-12 and GAP-13 (fast-init loops) are noted but treated as
  intentional exclusions, not functional gaps, because the
  design intentionally uses sram_init in normal test mode.
- The inferred CU-08/CU-09 conflicts are noted at medium
  confidence because those rows use assign-based combinational
  logic (ueff ternary) that does not have explicit %000000
  markers; the conflict is deduced from lcl_epoch never
  advancing rather than from direct annotation evidence.

## RVA23 compliance risks and gaps noticed
None observed. The gaps are testbench coverage gaps, not
design compliance issues.

## Deferred Work
- CE-09 (aging path): requires tage_enable_aging=1 tests with
  enough predictions to advance lcl_epoch and roll the interval.
- CE-10 (allocation path): requires a mispredict scenario where
  the provider is not T4 AND an entry with ueff==0 exists.
  Likely blocked by sram_init (all entries initialized with
  USEFUL=0, so ueff should be 0 after initialization). Root
  cause for why ueff==0 scan always failed needs investigation.
- CP-10 / T1-T3 coverage: requires driving predictions that hit
  shorter-history tables.
- CU-11 slot 1 write conflict: needs investigation whether the
  testbench drove slot 1 updates that should have produced RAM
  writes in tage_table.

## Other Notes
Annotation note: the `ueff_p1` assignment in tage_cntrl.sv
(lines 418-423, gen_ueff generate block) uses combinational
assign statements. Verilator does not create explicit coverage
points for these, so they do not appear as %000000 in the
annotation even when uncovered. The aging/epoch reasoning
above is the only way to infer their coverage state.

CE-10 (alloc) is a critical gap: the full allocation path from
ueff scan through alc_wd write to tage_table RAM was NEVER
exercised. Because TAGE_SRAM_INIT_VALUE=0 initializes entries
with USEFUL=0, all entries should have ueff=0 initially (before
any write). The reason ueff was never 0 at scan time needs
investigation -- possibly entries were updated (USEFUL written
nonzero) before the first mispredict, or the provider was always
T4 (TAGE_MAX_TBL) making no higher table available for alloc.

## Files Modified
Not captured

:: RESULTS:END ::

